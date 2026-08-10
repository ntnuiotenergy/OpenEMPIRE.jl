function _trace(
        ;
        x,
        y,
        name::AbstractString,
        type::AbstractString,
        mode::Union{Nothing, AbstractString} = nothing,
        color::Union{Nothing, AbstractString} = nothing,
        hovertemplate::Union{Nothing, AbstractString} = nothing,
    )
    fields = [
        "\"x\": $(_js_array(x))",
        "\"y\": $(_js_array(y))",
        "\"name\": $(_js_string(name))",
        "\"type\": $(_js_string(type))",
    ]
    mode === nothing || push!(fields, "\"mode\": $(_js_string(mode))")
    hovertemplate === nothing || push!(fields, "\"hovertemplate\": $(_js_string(hovertemplate))")
    if color !== nothing
        if type == "bar"
            push!(fields, "\"marker\": {\"color\": $(_js_string(color))}")
        else
            push!(fields, "\"line\": {\"color\": $(_js_string(color))}")
            push!(fields, "\"marker\": {\"color\": $(_js_string(color))}")
        end
    end
    return "{" * join(fields, ", ") * "}"
end

function _scattergeo_trace(
        ;
        lon,
        lat,
        name::AbstractString,
        mode::AbstractString,
        text = nothing,
        line_color::Union{Nothing, AbstractString} = nothing,
        line_width::Union{Nothing, Real} = nothing,
        marker_color::Union{Nothing, AbstractString} = nothing,
        marker_size::Union{Nothing, Real} = nothing,
        textposition::Union{Nothing, AbstractString} = nothing,
        hoverinfo::Union{Nothing, AbstractString} = nothing,
        visible::Bool = true,
    )
    fields = [
        "\"type\": \"scattergeo\"",
        "\"lon\": $(_js_array(lon))",
        "\"lat\": $(_js_array(lat))",
        "\"name\": $(_js_string(name))",
        "\"mode\": $(_js_string(mode))",
    ]
    text === nothing || push!(fields, "\"text\": $(_js_array(text))")
    textposition === nothing || push!(fields, "\"textposition\": $(_js_string(textposition))")
    hoverinfo === nothing || push!(fields, "\"hoverinfo\": $(_js_string(hoverinfo))")
    visible || push!(fields, "\"visible\": false")
    if line_color !== nothing || line_width !== nothing
        line_fields = String[]
        line_color === nothing || push!(line_fields, "\"color\": $(_js_string(line_color))")
        line_width === nothing || push!(line_fields, "\"width\": $(_js_value(line_width))")
        push!(fields, "\"line\": {" * join(line_fields, ", ") * "}")
    end
    if marker_color !== nothing || marker_size !== nothing
        marker_fields = String[]
        marker_color === nothing || push!(marker_fields, "\"color\": $(_js_string(marker_color))")
        marker_size === nothing || push!(marker_fields, "\"size\": $(_js_value(marker_size))")
        push!(fields, "\"marker\": {" * join(marker_fields, ", ") * "}")
    end
    return "{" * join(fields, ", ") * "}"
end

"""
Hourly values are rounded before they reach the page. Three decimals is far below
any meaningful MW resolution, and full `Float64` printing roughly doubles the size
of a dispatch page for no gain.
"""
_dispatch_round(value::Real) = round(Float64(value); digits = 3)

function _dispatch_area_trace(
        x,
        y,
        name::AbstractString,
        stackgroup::AbstractString,
        color::AbstractString,
        visible::Bool,
    )
    fields = [
        "\"x\": $(_js_array(x))",
        "\"y\": $(_js_array(_dispatch_round.(y)))",
        "\"name\": $(_js_string(name))",
        "\"type\": \"scatter\"",
        "\"mode\": \"lines\"",
        "\"stackgroup\": $(_js_string(stackgroup))",
        "\"line\": {\"width\": 0.5, \"color\": $(_js_string(color))}",
        "\"fillcolor\": $(_js_string(color))",
        "\"hovertemplate\": $(_js_string("%{y:.1f} MW<extra>$name</extra>"))",
    ]
    visible || push!(fields, "\"visible\": false")
    return "{" * join(fields, ", ") * "}"
end

function _dispatch_line_trace(
        x,
        y,
        name::AbstractString,
        color::AbstractString,
        dash::AbstractString,
        axis::AbstractString,
        visible::Bool,
    )
    unit = axis == "y2" ? "EUR/MWh" : "MW"
    fields = [
        "\"x\": $(_js_array(x))",
        "\"y\": $(_js_array(_dispatch_round.(y)))",
        "\"name\": $(_js_string(name))",
        "\"type\": \"scatter\"",
        "\"mode\": \"lines\"",
        "\"line\": {\"width\": 1.6, \"color\": $(_js_string(color)), \"dash\": $(_js_string(dash))}",
        "\"hovertemplate\": $(_js_string("%{y:.1f} $unit<extra>$name</extra>"))",
    ]
    axis == "y" || push!(fields, "\"yaxis\": $(_js_string(axis))")
    visible || push!(fields, "\"visible\": false")
    return "{" * join(fields, ", ") * "}"
end

"""
    _dispatch_layout(title, base_title, periods, period_trace_indices, trace_count, active_period, season_last_hour)

Two y-axes (power left, price right), a vertical rule at each season boundary,
and a period dropdown.

`Hour` runs as one index across the concatenated seasons, so the boundaries are
where the reader would otherwise mistake a discontinuity for a ramp.
"""
function _dispatch_layout(
        title::AbstractString,
        base_title::AbstractString,
        periods::AbstractVector{<:AbstractString},
        period_trace_indices::Dict{String, Vector{Int}},
        trace_count::Integer,
        active_period::AbstractString,
        season_last_hour::Dict{String, Int},
    )
    boundaries = sort!(collect(season_last_hour); by = pair -> pair[2])
    shapes = String[]
    annotations = String[]
    for (season, hour) in boundaries
        push!(
            shapes,
            "{\"type\": \"line\", \"xref\": \"x\", \"yref\": \"paper\", " *
            "\"x0\": $hour, \"x1\": $hour, \"y0\": 0, \"y1\": 1, " *
            "\"line\": {\"color\": \"#999999\", \"width\": 1, \"dash\": \"dot\"}}",
        )
        push!(
            annotations,
            "{\"x\": $hour, \"xref\": \"x\", \"yref\": \"paper\", \"y\": 1.02, " *
            "\"text\": $(_js_string(season)), \"showarrow\": false, " *
            "\"font\": {\"size\": 10, \"color\": \"#666666\"}, \"xanchor\": \"right\"}",
        )
    end

    fields = [
        "\"title\": $(_js_string(title))",
        "\"xaxis\": {\"title\": \"Hour\"}",
        "\"yaxis\": {\"title\": \"Power [MW]\", \"zeroline\": true, \"zerolinecolor\": \"#888888\"}",
        "\"yaxis2\": {\"title\": \"Price [EUR/MWh]\", \"overlaying\": \"y\", \"side\": \"right\", \"showgrid\": false}",
        "\"legend\": {\"orientation\": \"h\", \"y\": -0.18}",
        "\"margin\": {\"l\": 70, \"r\": 70, \"t\": 90, \"b\": 70}",
        "\"hovermode\": \"x unified\"",
        "\"shapes\": [" * join(shapes, ", ") * "]",
        "\"annotations\": [" * join(annotations, ", ") * "]",
    ]
    if !isempty(periods)
        push!(
            fields,
            "\"updatemenus\": $(_label_dropdown(periods, period_trace_indices, trace_count, base_title, active_period))",
        )
    end
    return "{" * join(fields, ", ") * "}"
end

"""
    _label_dropdown(labels, label_trace_indices, trace_count, base_title, active_label)

String-labelled sibling of [`_period_dropdown`](@ref). Report tables label periods
`"2020-2025"` rather than with an index, so the integer version cannot be reused.
"""
function _label_dropdown(
        labels::AbstractVector{<:AbstractString},
        label_trace_indices::Dict{String, Vector{Int}},
        trace_count::Integer,
        base_title::AbstractString,
        active_label::AbstractString,
    )
    buttons = String[]
    for label in labels
        visible = falses(trace_count)
        for trace_index in get(label_trace_indices, String(label), Int[])
            visible[trace_index] = true
        end
        push!(
            buttons,
            "{" *
            join([
                "\"label\": $(_js_string(label))",
                "\"method\": \"update\"",
                "\"args\": [{\"visible\": $(_js_array(visible))}, {\"title\": $(_js_string("$base_title ($label)"))}]",
            ], ", ") *
            "}",
        )
    end
    # As in `_period_dropdown`: `findfirst` returns `nothing` when the active
    # label is not among `labels`, and `nothing - 1` would throw.
    active_index = something(findfirst(==(active_label), labels), length(labels))
    return "[" * "{" * join([
        "\"buttons\": [" * join(buttons, ", ") * "]",
        "\"direction\": \"down\"",
        "\"showactive\": true",
        "\"active\": $(active_index - 1)",
        "\"x\": 0.02",
        "\"xanchor\": \"left\"",
        "\"y\": 1.14",
        "\"yanchor\": \"top\"",
    ], ", ") * "}" * "]"
end

function _layout(
        title::AbstractString,
        x_title::AbstractString,
        y_title::AbstractString;
        barmode::Union{Nothing, AbstractString} = nothing,
        x_values = nothing,
    )
    xaxis_fields = [
        "\"title\": $(_js_string(x_title))",
        "\"type\": \"category\"",
    ]
    x_values === nothing || push!(xaxis_fields, "\"categoryarray\": $(_js_array(x_values))")
    fields = [
        "\"title\": $(_js_string(title))",
        "\"xaxis\": {" * join(xaxis_fields, ", ") * "}",
        "\"yaxis\": {\"title\": $(_js_string(y_title))}",
        "\"legend\": {\"orientation\": \"h\"}",
        "\"margin\": {\"l\": 70, \"r\": 20, \"t\": 70, \"b\": 70}",
    ]
    barmode === nothing || push!(fields, "\"barmode\": $(_js_string(barmode))")
    return "{" * join(fields, ", ") * "}"
end

function _geo_layout(
        title::AbstractString,
        periods::AbstractVector{<:Integer} = Int[],
        period_trace_indices::Dict{Int, Vector{Int}} = Dict{Int, Vector{Int}}(),
        trace_count::Integer = 0,
        base_title::AbstractString = title,
        active_period::Integer = isempty(periods) ? 0 : last(periods),
    )
    updatemenus = isempty(periods) ? nothing : _period_dropdown(periods, period_trace_indices, trace_count, base_title, active_period)
    fields = [
        "\"title\": $(_js_string(title))",
        "\"geo\": {\"scope\": \"europe\", \"showland\": true, \"landcolor\": \"#f5f5f5\", \"showcountries\": true, \"countrycolor\": \"#bbbbbb\", \"projection\": {\"type\": \"natural earth\"}}",
        "\"legend\": {\"orientation\": \"h\"}",
        "\"margin\": {\"l\": 20, \"r\": 20, \"t\": 70, \"b\": 20}",
    ]
    updatemenus === nothing || push!(fields, "\"updatemenus\": $updatemenus")
    return "{" * join(fields, ", ") * "}"
end

function _period_dropdown(
        periods::AbstractVector{<:Integer},
        period_trace_indices::Dict{Int, Vector{Int}},
        trace_count::Integer,
        base_title::AbstractString,
        active_period::Integer,
    )
    buttons = String[]
    for period in periods
        visible = falses(trace_count)
        for trace_index in get(period_trace_indices, Int(period), Int[])
            visible[trace_index] = true
        end
        push!(
            buttons,
            "{" *
            join([
                "\"label\": $(_js_string("Period $period"))",
                "\"method\": \"update\"",
                "\"args\": [{\"visible\": $(_js_array(visible))}, {\"title\": $(_js_string("$base_title - Period $period"))}]",
            ], ", ") *
            "}",
        )
    end
    # Fall back to the last period when `active_period` is not among `periods`;
    # `findfirst` returns `nothing` there and `nothing - 1` would throw.
    active_index = something(findfirst(==(active_period), periods), length(periods))
    return "[" * "{" * join([
        "\"buttons\": [" * join(buttons, ", ") * "]",
        "\"direction\": \"down\"",
        "\"showactive\": true",
        "\"active\": $(active_index - 1)",
        "\"x\": 0.02",
        "\"xanchor\": \"left\"",
        "\"y\": 1.08",
        "\"yanchor\": \"top\"",
    ], ", ") * "}" * "]"
end

const PLOTLY_CDN_URL = "https://cdn.plot.ly/plotly-2.35.2.min.js"
const PLOTLY_VENDOR_FILENAME = "plotly.min.js"

"""
    _plotly_script_tag(plot_dir)

Reference a vendored `plotly.min.js` sitting next to the generated HTML when one
is present, and fall back to the CDN otherwise.

Runs are produced on Solstorm and read afterwards, often from an archived copy or
a machine without network access. A bare CDN tag renders a silently blank page in
that situation, so `write_result_plots(...; plotly_js = "/path/to/plotly.min.js")`
copies the library into the plot directory and every page then loads offline.
"""
function _plotly_script_tag(plot_dir::AbstractString)
    if isfile(joinpath(plot_dir, PLOTLY_VENDOR_FILENAME))
        return "<script src=\"$PLOTLY_VENDOR_FILENAME\"></script>"
    end
    return "<script src=\"$PLOTLY_CDN_URL\"></script>"
end

# Shown only if `Plotly` is still undefined once the page has parsed, i.e. the
# CDN was unreachable. Without it the viewer just sees an empty page.
const PLOTLY_FALLBACK_NOTICE = """
    <div id="plotly-missing" style="display:none; margin: 16px 0; padding: 12px 16px; border: 1px solid #d9534f; background: #fdf3f2; color: #a33; max-width: 960px;">
      <strong>Plots could not be rendered.</strong>
      The Plotly library was not reachable, most likely because this page is being
      viewed without internet access. Re-generate with
      <code>plotly_js = "/path/to/plotly.min.js"</code> to embed the library
      alongside the results so the dashboard works offline.
    </div>
    """

const PLOTLY_FALLBACK_SCRIPT = """
    if (typeof Plotly === "undefined") {
      document.getElementById("plotly-missing").style.display = "block";
    } else {
    """

function _write_plotly_html(path::AbstractString, title::AbstractString, traces, layout::AbstractString)
    html = """
    <!doctype html>
    <html>
    <head>
      <meta charset="utf-8">
      <title>$(_html_escape(title))</title>
      $(_plotly_script_tag(dirname(path)))
      <style>
        body { font-family: system-ui, sans-serif; margin: 24px; }
        #plot { width: 100%; height: 760px; }
      </style>
    </head>
    <body>
    $PLOTLY_FALLBACK_NOTICE
      <div id="plot"></div>
      <script>
        $PLOTLY_FALLBACK_SCRIPT
        const data = [$(join(traces, ","))];
        const layout = $layout;
        Plotly.newPlot("plot", data, layout, {responsive: true});
        }
      </script>
    </body>
    </html>
    """
    write(path, html)
    return path
end

function _plot_sections(plots, start_index::Integer)
    sections = String[]
    scripts = String[]
    for (offset, plot) in enumerate(plots)
        index = start_index + offset - 1
        div_id = "plot-$index"
        push!(
            sections,
            """
            <section>
              <h2>$(_html_escape(plot.title))</h2>
              <p><a href=\"$(_html_escape(plot.filename))\">Open standalone plot</a></p>
              $(_note_html(plot.note))
              <div id="$div_id" class="plot"></div>
            </section>
            """,
        )
        push!(
            scripts,
            """
            Plotly.newPlot("$div_id", [$(join(plot.traces, ","))], $(plot.layout), {responsive: true});
            """,
        )
    end
    return join(sections, "\n"), join(scripts, "\n")
end

"""
    _dispatch_index_html(plots)

Render the per-node dispatch pages as a link index rather than embedded plots.

There is one page per node, each carrying every period, so `europe_v51` would
otherwise inline ~70 MB of traces into `dashboard.html`.
"""
function _dispatch_index_html(plots)
    isempty(plots) && return ""
    links = String[]
    for plot in plots
        label = replace(plot.title, "Hourly Dispatch - " => "")
        push!(links, "<li><a href=\"$(_html_escape(plot.filename))\">$(_html_escape(label))</a></li>")
    end
    note = _note_html(first(plots).note)
    return """
    <section>
      <h2>Hourly Dispatch by Node</h2>
      $note
      <ul class="node-index">
      $(join(links, "\n"))
      </ul>
    </section>
    """
end

function _write_dashboard_html(path::AbstractString, result_plots, input_plots, dispatch_plots = NamedTuple[])
    result_sections, result_scripts = _plot_sections(result_plots, 1)
    input_sections, input_scripts = _plot_sections(input_plots, length(result_plots) + 1)
    dispatch_sections = _dispatch_index_html(dispatch_plots)
    input_button = isempty(input_plots) ? "" : "<button class=\"tab-button\" onclick=\"showTab('inputs', event)\">Inputs</button>"
    dispatch_button = isempty(dispatch_plots) ? "" : "<button class=\"tab-button\" onclick=\"showTab('dispatch', event)\">Dispatch</button>"

    html = """
    <!doctype html>
    <html>
    <head>
      <meta charset="utf-8">
      <title>OpenEMPIRE Results Dashboard</title>
      $(_plotly_script_tag(dirname(path)))
      <style>
        body { font-family: system-ui, sans-serif; margin: 24px; color: #222; }
        h1 { margin-bottom: 8px; }
        h2 { margin: 0 0 4px; font-size: 18px; }
        .tabs { display: flex; gap: 8px; border-bottom: 1px solid #ddd; margin-top: 24px; }
        .tab-button { background: #f7f7f7; border: 1px solid #ddd; border-bottom: none; padding: 10px 14px; cursor: pointer; }
        .tab-button.active { background: #fff; font-weight: 700; }
        .tab-panel { display: none; }
        .tab-panel.active { display: block; }
        section { border-top: 1px solid #ddd; padding-top: 24px; margin-top: 24px; }
        section p { margin: 0; }
        .note { margin-top: 8px; color: #555; max-width: 960px; }
        .plot { width: 100%; height: 680px; }
        .node-index { margin-top: 16px; padding: 0; list-style: none;
                      display: grid; grid-template-columns: repeat(auto-fill, minmax(180px, 1fr)); gap: 6px 16px; }
        .node-index a { text-decoration: none; color: #1f77b4; }
        .node-index a:hover { text-decoration: underline; }
      </style>
    </head>
    <body>
      <h1>OpenEMPIRE Results Dashboard</h1>
    $PLOTLY_FALLBACK_NOTICE
      <div class="tabs">
        <button class="tab-button active" onclick="showTab('results', event)">Results</button>
        $dispatch_button
        $input_button
      </div>
      <div id="results" class="tab-panel active">
      $result_sections
      </div>
      <div id="dispatch" class="tab-panel">
      $dispatch_sections
      </div>
      <div id="inputs" class="tab-panel">
      $input_sections
      </div>
      <script>
      function showTab(tabName, event) {
        for (const panel of document.querySelectorAll('.tab-panel')) {
          panel.classList.remove('active');
        }
        for (const button of document.querySelectorAll('.tab-button')) {
          button.classList.remove('active');
        }
        document.getElementById(tabName).classList.add('active');
        event.currentTarget.classList.add('active');
        window.dispatchEvent(new Event('resize'));
      }
      $PLOTLY_FALLBACK_SCRIPT
      $result_scripts
      $input_scripts
      }
      </script>
    </body>
    </html>
    """
    write(path, html)
    return path
end

_js_array(values) = "[" * join((_js_value(v) for v in values), ", ") * "]"
_js_value(value::AbstractString) = _js_string(value)
_js_value(value::Bool) = value ? "true" : "false"
_js_value(value::Integer) = string(value)
_js_value(value::Real) = isfinite(value) ? string(Float64(value)) : "null"

"""
    _js_string(value)

Emit a JavaScript string literal. Besides the usual backslash/quote escaping this
must neutralise two things that would otherwise produce a broken page rather than
a visibly wrong one: raw control characters (an embedded newline terminates the
literal) and the sequence `</script>`, which an HTML parser honours *inside* a
script block and which would end the block early. Node and generator names come
from user-supplied CSV, so neither is hypothetical.
"""
function _js_string(value::AbstractString)
    io = IOBuffer()
    print(io, '"')
    for character in value
        if character == '\\'
            print(io, "\\\\")
        elseif character == '"'
            print(io, "\\\"")
        elseif character == '\n'
            print(io, "\\n")
        elseif character == '\r'
            print(io, "\\r")
        elseif character == '\t'
            print(io, "\\t")
        elseif character == '<'
            # Breaks up "</script>" without altering the decoded string value.
            print(io, "\\u003c")
        elseif character < ' '
            print(io, "\\u", lpad(string(UInt16(character); base = 16), 4, '0'))
        else
            print(io, character)
        end
    end
    print(io, '"')
    return String(take!(io))
end

function _html_escape(value::AbstractString)
    return replace(value, "&" => "&amp;", "<" => "&lt;", ">" => "&gt;", "\"" => "&quot;")
end

_note_html(note::AbstractString) = isempty(note) ? "" : "<p class=\"note\">$(_html_escape(note))</p>"

