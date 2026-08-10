"""
    _category(value)

Normalise a category cell to a `String`. Period columns are plain integers in the
raw variable dumps (`genInvCap.csv`) but period *labels* in the aggregated report
tables (`results_output_gen.csv` writes `"2020-2025"`), so categories are carried
as strings everywhere and ordered by [`_sort_categories`](@ref).
"""
_category(value) = string(value)
_category(value::AbstractFloat) = string(isinteger(value) ? Int(value) : value)

"""
    _sort_categories(values)

Sort category labels so that numeric-looking labels order numerically rather than
lexicographically: `"2", "10"` and `"2020-2025", "2025-2030"` both come out in the
order a reader expects, while non-numeric labels fall back to plain string order.
"""
function _sort_categories(values)
    return sort!(collect(values); by = _category_sort_key)
end

function _category_sort_key(value::AbstractString)
    leading = match(r"^\s*(-?\d+(?:\.\d+)?)", value)
    leading === nothing && return (1, 0.0, String(value))
    return (0, parse(Float64, leading.captures[1]), String(value))
end

"""
    _read_csv_sections(csv_path)

Split a multi-section result CSV into one `CSV.File` per section.

`results_output_EuropeSummary.csv` and `results_output_EuropePlot.csv` concatenate
several tables with different headers into one file, separated by a blank line —
the same layout the Python `EmpireOutputClient` splits on. Handing the whole file
to `CSV.File` silently parses later sections against the first section's header,
which is how rows with six fields end up in an eleven-column table.

Sections are returned in file order; use [`_read_csv_section`](@ref) to pick one.
"""
function _read_csv_sections(csv_path::AbstractString)
    isfile(csv_path) || return CSV.File[]
    sections = CSV.File[]
    buffer = IOBuffer()
    lines_in_section = 0

    function flush_section!()
        if lines_in_section > 1
            push!(sections, CSV.File(take!(buffer); normalizenames = false))
        else
            take!(buffer)
        end
        lines_in_section = 0
        return nothing
    end

    for line in eachline(csv_path)
        if isempty(strip(line))
            flush_section!()
        else
            println(buffer, line)
            lines_in_section += 1
        end
    end
    flush_section!()
    return sections
end

"""
    _read_csv_section(csv_path, index = 1)

Return one section of a multi-section result CSV, or an empty row vector when the
file or that section is absent. Plain single-table CSVs have exactly one section,
so this is safe to use for them too.
"""
function _read_csv_section(csv_path::AbstractString, index::Integer = 1)
    sections = _read_csv_sections(csv_path)
    length(sections) < index && return NamedTuple[]
    return sections[index]
end

"""
Raw variable dumps above this size are skipped rather than plotted.

The diagnostic plots built on `genOperational.csv` and `loadShed.csv` go through
[`_group_sum`](@ref), which uses `CSV.File` and therefore materialises the whole
file before summing. These dumps hold one row per JuMP variable — node x
generator x period x scenario x hour — so on `europe_v51` at `run_2060`
`genOperational.csv` runs to hundreds of millions of rows and the dashboard never
finishes. It is 2.1 MB on `data/test`, so the threshold does not affect the
datasets these plots are actually useful for.

The weighted report tables are never subject to this: they are aggregated to
annual figures by `src/results.jl` and stay small at any dataset size. Hourly
detail at European scale is what the per-node dispatch pages are for, and those
stream their input instead of materialising it.
"""
const RAW_DUMP_MAX_BYTES = 100 * 1024 * 1024

"""
    _raw_dump_is_plottable(csv_path, label)

Whether a raw variable dump is present and small enough to aggregate in memory.

Warns rather than failing when it is too large: the dump feeds a diagnostic, and
losing one diagnostic is much better than losing the whole dashboard for a run
that took hours to solve.
"""
function _raw_dump_is_plottable(csv_path::AbstractString, label::AbstractString)
    isfile(csv_path) || return false
    size_bytes = filesize(csv_path)
    size_bytes <= RAW_DUMP_MAX_BYTES && return true
    @warn "Skipping \"$label\": raw variable dump is too large to aggregate in memory. " *
        "Use the per-node hourly dispatch pages for operational detail at this scale." *
        " file=$(basename(csv_path)) size=$(round(size_bytes / 1024^2; digits = 1))MB" *
        " limit=$(round(RAW_DUMP_MAX_BYTES / 1024^2; digits = 1))MB"
    return false
end

function _group_sum(
        csv_path::AbstractString,
        x_col::Union{Symbol, Integer},
        series_col::Union{Symbol, Integer},
        value_col::Union{Symbol, Integer};
        series_mapper = identity,
    )
    grouped = Dict{Tuple{String, String}, Float64}()
    for row in CSV.File(csv_path; normalizenames = false)
        key = (_category(row[x_col]), string(series_mapper(string(row[series_col]))))
        grouped[key] = get(grouped, key, 0.0) + _number(row[value_col])
    end
    return grouped
end

"""
    _number(value)

Coerce a CSV cell to `Float64`, mapping empty/`missing` cells to `0.0`. Result
tables legitimately contain blanks (e.g. a dual that was not computed), and
`Float64(missing)` would otherwise abort the whole dashboard.
"""
_number(value::Real) = Float64(value)
_number(::Missing) = 0.0
_number(::Nothing) = 0.0
function _number(value::AbstractString)
    stripped = strip(value)
    isempty(stripped) && return 0.0
    parsed = tryparse(Float64, stripped)
    return parsed === nothing ? 0.0 : parsed
end
_number(value) = Float64(value)

"""
    _integer(value)

Coerce a CSV cell to `Int`. `CSV.Rows` hands back unparsed string cells, so the
streamed operational table needs this where `CSV.File` would already have typed
the column.
"""
_integer(value::Integer) = Int(value)
_integer(value::Real) = Int(round(value))
_integer(::Missing) = 0
_integer(::Nothing) = 0
function _integer(value::AbstractString)
    stripped = strip(value)
    isempty(stripped) && return 0
    parsed = tryparse(Int, stripped)
    parsed === nothing || return parsed
    return Int(round(_number(stripped)))
end
_integer(value) = Int(value)

"""
The input transmission CSVs are read by column position, not by header name,
because the header names drift between datasets while the layout does not:

| File | `test` | `europe_v50` | `europe_v51` |
|---|---|---|---|
| `transmissionInitCap.csv` | `InterconnectorLinks` | `FromNode` | `InterconnectorLinks` |
| `transmissionLength.csv` | `lineLength_in_km` | `lineLength_in_km` | `Length_in_km` |

`src/read_csv.jl` already reads these same files positionally
(`_read_float_by_pair_csv`, `_read_strategic_profiles_pair_csv`), which is why the
model loads all three datasets while a name-based read here does not. Match it.
"""
function _read_arc_period_values(
        csv_path::AbstractString;
        from_col::Int = 1,
        to_col::Int = 2,
        period_col::Int = 3,
        value_col::Int = 4,
    )
    values = Dict{Tuple{String, String, Int}, Float64}()
    isfile(csv_path) || return values

    for row in CSV.File(csv_path; normalizenames = false)
        from_node = string(row[from_col])
        to_node = string(row[to_col])
        period = Int(row[period_col])
        values[(from_node, to_node, period)] = _number(row[value_col])
    end
    return values
end

function _read_arc_values(
        csv_path::AbstractString;
        from_col::Int = 1,
        to_col::Int = 2,
        value_col::Int = 3,
    )
    values = Dict{Tuple{String, String}, Float64}()
    isfile(csv_path) || return values

    for row in CSV.File(csv_path; normalizenames = false)
        values[(string(row[from_col]), string(row[to_col]))] = _number(row[value_col])
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

"""
One step up the unit ladder, applied when an axis would otherwise be read in
scientific-ish shorthand.
"""
const _UNIT_STEP_UP = Dict(
    "GWh" => "TWh",
    "MWh" => "GWh",
    "MW" => "GW",
    "MEUR" => "BEUR",
)

"""
Rescale above this stacked peak, in whatever unit the axis is already in.

`europe_v51` annual generation peaks near 8e6 GWh, which Plotly renders as an
axis labelled `8M` — technically correct and unreadable. In TWh it reads 8000.
`data/test` peaks around 1e3 GWh and stays in GWh, so the small dataset's numbers
(and the assertions pinned to them) are untouched.
"""
const UNIT_RESCALE_THRESHOLD = 1.0e5

"""
    _rescale_unit(grouped, y_title, stack_key)

Divide grouped values by 1000 and step the axis unit up, when the largest stacked
column warrants it. Returns the values and title unchanged otherwise.

The peak is the stacked total per column, not the largest single value: it is the
axis maximum that decides whether the labels are readable.
"""
function _rescale_unit(grouped::Dict, y_title::AbstractString, stack_key::Function)
    unit = _unit_suffix(y_title)
    stepped = get(_UNIT_STEP_UP, unit, nothing)
    stepped === nothing && return grouped, y_title

    stacks = Dict{Any, Float64}()
    for (key, value) in grouped
        value > 0 || continue
        column = stack_key(key)
        stacks[column] = get(stacks, column, 0.0) + value
    end
    peak = isempty(stacks) ? 0.0 : maximum(values(stacks))
    peak < UNIT_RESCALE_THRESHOLD && return grouped, y_title

    rescaled = Dict(key => value / 1000 for (key, value) in grouped)
    return rescaled, replace(y_title, "[$unit]" => "[$stepped]")
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

