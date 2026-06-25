function _group_sum(
        csv_path::AbstractString,
        x_col::Symbol,
        series_col::Symbol,
        value_col::Symbol;
        series_mapper = identity,
    )
    grouped = Dict{Tuple{Int, String}, Float64}()
    for row in CSV.File(csv_path; normalizenames = false)
        key = (Int(row[x_col]), string(series_mapper(string(row[series_col]))))
        grouped[key] = get(grouped, key, 0.0) + Float64(row[value_col])
    end
    return grouped
end

function _read_arc_period_values(
        csv_path::AbstractString,
        from_col::Symbol,
        to_col::Symbol,
        period_col::Symbol,
        value_col::Symbol,
    )
    values = Dict{Tuple{String, String, Int}, Float64}()
    isfile(csv_path) || return values

    for row in CSV.File(csv_path; normalizenames = false)
        from_node = string(row[from_col])
        to_node = string(row[to_col])
        period = Int(row[period_col])
        values[(from_node, to_node, period)] = Float64(row[value_col])
    end
    return values
end

function _read_arc_values(csv_path::AbstractString, from_col::Symbol, to_col::Symbol, value_col::Symbol)
    values = Dict{Tuple{String, String}, Float64}()
    isfile(csv_path) || return values

    for row in CSV.File(csv_path; normalizenames = false)
        values[(string(row[from_col]), string(row[to_col]))] = Float64(row[value_col])
    end
    return values
end

function _corridor_key(from_node::AbstractString, to_node::AbstractString)
    return from_node <= to_node ? (String(from_node), String(to_node)) : (String(to_node), String(from_node))
end

function _value_for_corridor_period(values::Dict{Tuple{String, String, Int}, Float64}, from_node::AbstractString, to_node::AbstractString, period::Integer)
    return get(values, (String(from_node), String(to_node), Int(period)), get(values, (String(to_node), String(from_node), Int(period)), 0.0))
end

function _value_for_corridor(values::Dict{Tuple{String, String}, Float64}, from_node::AbstractString, to_node::AbstractString)
    return get(values, (String(from_node), String(to_node)), get(values, (String(to_node), String(from_node)), 0.0))
end

function _line_type_for_corridor(transmission_line_types::Dict{Tuple{String, String}, String}, from_node::AbstractString, to_node::AbstractString)
    return get(transmission_line_types, (String(from_node), String(to_node)), get(transmission_line_types, (String(to_node), String(from_node)), "Unknown"))
end

function _generator_family(generator::AbstractString)
    lowercase_generator = lowercase(generator)
    contains(lowercase_generator, "windoffshore") && return "Wind offshore"
    contains(lowercase_generator, "wind_offshr") && return "Wind offshore"
    contains(lowercase_generator, "windonshore") && return "Wind onshore"
    contains(lowercase_generator, "wind_onshr") && return "Wind onshore"
    contains(lowercase_generator, "solar") && return "Solar"
    contains(lowercase_generator, "hydrorun") && return "Hydro run-of-river"
    contains(lowercase_generator, "hydro_ror") && return "Hydro run-of-river"
    contains(lowercase_generator, "hydroregulated") && return "Hydro regulated"
    contains(lowercase_generator, "hydro_reg") && return "Hydro regulated"
    contains(lowercase_generator, "nuclear") && return "Nuclear"
    contains(lowercase_generator, "wave") && return "Wave"
    contains(lowercase_generator, "geo") && return "Geothermal"
    contains(lowercase_generator, "waste") && return "Waste"
    contains(lowercase_generator, "bio10cofiringccs") && return "Bio cofiring CCS"
    contains(lowercase_generator, "bio10cofiring") && return "Bio cofiring"
    contains(lowercase_generator, "cofire") && return "Bio cofiring"
    contains(lowercase_generator, "bio") && return "Bio"
    contains(lowercase_generator, "gas") && contains(lowercase_generator, "ccs") && return "Gas CCS"
    contains(lowercase_generator, "gas") && return "Gas"
    contains(lowercase_generator, "coal") && contains(lowercase_generator, "ccs") && return "Coal CCS"
    contains(lowercase_generator, "coal") && return "Coal"
    contains(lowercase_generator, "lignite") && contains(lowercase_generator, "ccs") && return "Lignite CCS"
    contains(lowercase_generator, "liginite") && contains(lowercase_generator, "ccs") && return "Lignite CCS"
    contains(lowercase_generator, "lignite") && return "Lignite"
    contains(lowercase_generator, "liginite") && return "Lignite"
    contains(lowercase_generator, "oil") && return "Oil"
    lowercase_generator == "ccs" && return "CCS"
    lowercase_generator == "existing" && return "Existing"
    return String(generator)
end

function _series_color(series::AbstractString)
    return get(RESULT_SERIES_COLORS, series, _fallback_color(series))
end

function _transmission_type_color(line_type::AbstractString)
    return get(TRANSMISSION_TYPE_COLORS, line_type, "#2E86AB")
end

function _has_nonzero(values)
    return any(value -> abs(Float64(value)) > 1.0e-9, values)
end

function _hover_template(y_title::AbstractString)
    unit = _unit_suffix(y_title)
    value = isempty(unit) ? "%{y:,.1f}" : "%{y:,.1f} $unit"
    return "%{x}<br>%{fullData.name}: $value<extra></extra>"
end

function _unit_suffix(y_title::AbstractString)
    start_index = findfirst('[', y_title)
    end_index = findfirst(']', y_title)
    (start_index === nothing || end_index === nothing || end_index <= start_index) && return ""
    return y_title[nextind(y_title, start_index):prevind(y_title, end_index)]
end

function _format_value(value::Real)
    return string(round(Float64(value); digits = 2))
end

function _fallback_color(series::AbstractString)
    palette = (
        "#1f77b4",
        "#ff7f0e",
        "#2ca02c",
        "#d62728",
        "#9467bd",
        "#8c564b",
        "#e377c2",
        "#7f7f7f",
        "#bcbd22",
        "#17becf",
    )
    index = mod(sum(Int(c) for c in series), length(palette)) + 1
    return palette[index]
end

