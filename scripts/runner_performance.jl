struct JObj
    pairs::Vector{Pair{String, Any}}
end

function _json_escape(value)
    return replace(
        string(value),
        "\\" => "\\\\",
        "\"" => "\\\"",
        "\n" => "\\n",
        "\t" => "\\t",
    )
end

function _json(value)
    if value === nothing
        return "null"
    elseif value isa Bool
        return value ? "true" : "false"
    elseif value isa Integer
        return string(value)
    elseif value isa AbstractFloat
        return isfinite(value) ? string(value) : "null"
    elseif value isa Union{AbstractString, Symbol}
        return "\"$(_json_escape(value))\""
    elseif value isa JObj
        entries = (
            "\"$(_json_escape(key))\":" * _json(entry) for
            (key, entry) in value.pairs
        )
        return "{$(join(entries, ","))}"
    elseif value isa AbstractVector
        return "[$(join((_json(entry) for entry in value), ","))]"
    end
    return "\"$(_json_escape(value))\""
end

function _write_perf_json(path::AbstractString, object::JObj)
    mkpath(dirname(path))
    write(path, _json(object) * "\n")
    return path
end

function _perf_enabled()
    return lowercase(strip(get(ENV, "EMPIRE_PERF", ""))) in
           ("1", "true", "yes", "on")
end

function _perf_phase(
    name::AbstractString,
    wall_seconds::Real;
    alloc_bytes = nothing,
    gc_seconds = nothing,
)
    return JObj([
        "name" => name,
        "wall_seconds" => round(Float64(wall_seconds); digits = 3),
        "alloc_bytes" => alloc_bytes === nothing ? nothing : Int(alloc_bytes),
        "gc_seconds" => gc_seconds === nothing ?
                        nothing :
                        round(Float64(gc_seconds); digits = 3),
        "rss_peak_bytes" => Int(Sys.maxrss()),
        "live_bytes" => Int(Base.gc_live_bytes()),
    ])
end

function _pkgversion_str(package_module::Module)
    try
        version = pkgversion(package_module)
        return version === nothing ? nothing : string(version)
    catch
        return nothing
    end
end

function _family_cref_count(object)
    object isa JuMP.ConstraintRef && return 1
    object isa AbstractArray &&
        return count(value -> value isa JuMP.ConstraintRef, object)
    return 0
end

function report_constraint_family_counts(model::JuMP.Model)
    counts = Tuple{String, Int}[]
    for (name, object) in JuMP.object_dictionary(model)
        count = _family_cref_count(object)
        count > 0 && push!(counts, (string(name), count))
    end
    sort!(counts; by = first)

    println("Constraint family counts:")
    total = 0
    for (name, count) in counts
        total += count
        println("  $name: $count")
    end
    println("  TOTAL (named families): $total")
    flush(stdout)
    return counts
end
