include(joinpath(@__DIR__, "..", "postprocessing", "OpenEMPIREResults", "src", "OpenEMPIREResults.jl"))

const _Results = OpenEMPIREResults

function _write_text(path, content)
    mkpath(dirname(path))
    write(path, content)
    return path
end

"""
Minimal stand-in for a solved run's output directory.

Column names and the multi-section layout of `results_output_EuropeSummary.csv`
mirror what `src/results.jl` actually writes; the numbers are chosen so each
assertion below has a single obvious expected value.
"""
function _write_fake_output(output_dir)
    _write_text(
        joinpath(output_dir, "results_output_gen.csv"),
        """
        Node,GeneratorType,Period,genInvCap_MW,genInstalledCap_MW,genExpectedCapacityFactor,DiscountedInvestmentCost_Euro,genExpectedAnnualProduction_GWh
        NO,Windonshore,2020-2025,100.0,200.0,0.4,1.0e6,700.8
        SE,Windonshore,2020-2025,50.0,100.0,0.4,5.0e5,350.4
        NO,Windonshore,2025-2030,0.0,300.0,0.4,0.0,1051.2
        NO,Nuclear,2020-2025,0.0,10.0,0.9,0.0,78.84
        """,
    )
    _write_text(
        joinpath(output_dir, "results_output_stor.csv"),
        """
        Node,StorageType,Period,storPWInvCap_MW,storPWInstalledCap_MW,storENInvCap_MWh,storENInstalledCap_MWh,DiscountedInvestmentCostPWEN_EuroPerMWMWh,ExpectedAnnualDischargeVolume_GWh,ExpectedAnnualLossesChargeDischarge_GWh
        NO,Li-Ion_BESS,2020-2025,10.0,10.0,40.0,40.0,2.0e6,5.0,0.5
        """,
    )
    _write_text(
        joinpath(output_dir, "results_output_transmission.csv"),
        """
        BetweenNode,AndNode,Period,transmissionInvCap_MW,transmissionInstalledCap_MW,DiscountedInvestmentCost_Euro,transmissionExpectedAnnualVolume_GWh,ExpectedAnnualLosses_GWh
        NO,SE,2020-2025,500.0,1500.0,3.0e6,120.0,3.0
        NO,SE,2025-2030,0.0,1500.0,0.0,140.0,3.5
        """,
    )
    # Two sections separated by a blank line, as results.jl writes it.
    _write_text(
        joinpath(output_dir, "results_output_EuropeSummary.csv"),
        """
        Period,Scenario,AnnualCO2emission_Ton,CO2Price_EuroPerTon,CO2Cap_Ton,AnnualGeneration_GWh,AvgCO2factor_TonPerMWh,AvgELPrice_EuroPerMWh,TotAnnualCurtailedRES_GWh,TotAnnualLossesChargeDischarge_GWh,AnnualLossesTransmission_GWh
        2020-2025,scenario1,1.0e8,0.0,2.0e8,1000.0,0.1,40.0,10.0,1.0,2.0
        2020-2025,scenario2,1.4e8,0.0,2.0e8,1200.0,0.12,50.0,20.0,3.0,4.0

        GeneratorType,Period,genInvCap_MW,genInstalledCap_MW,TotDiscountedInvestmentCost_Euro,genExpectedAnnualProduction_GWh
        Windonshore,2020-2025,150.0,300.0,1.5e6,1051.2
        """,
    )
    return output_dir
end

function test_postprocessing_helpers()
    @testset "output directory casing" begin
        # The runner writes `output`; the Python reference and the package default
        # say `Output`. Both must resolve, or Solstorm runs break.
        #
        # Asserting the exact returned string cannot distinguish the two on a
        # case-insensitive filesystem (Windows, default macOS), where `isdir`
        # accepts either spelling. The property that actually matters, and that
        # does discriminate on Linux, is that the resolved path exists.
        for casing in ("output", "Output")
            mktempdir() do root
                mkpath(joinpath(root, casing))
                resolved = _Results._resolve_output_dir(root)
                @test isdir(resolved)
                @test lowercase(basename(resolved)) == "output"
            end
        end

        mktempdir() do root
            # Nothing to find: fall back to the documented default so the caller
            # can report a path rather than crash.
            @test _Results._resolve_output_dir(root) == joinpath(root, "Output")
        end
    end

    @testset "multi-section CSV" begin
        mktempdir() do root
            path = joinpath(root, "multi.csv")
            _write_fake_output(root)
            summary = joinpath(root, "results_output_EuropeSummary.csv")
            sections = _Results._read_csv_sections(summary)
            @test length(sections) == 2

            first_section = collect(_Results._read_csv_section(summary, 1))
            @test length(first_section) == 2
            @test all(row -> hasproperty(row, :Scenario), first_section)

            second_section = collect(_Results._read_csv_section(summary, 2))
            @test length(second_section) == 1
            @test second_section[1].GeneratorType == "Windonshore"

            # Asking past the end must not throw.
            @test isempty(_Results._read_csv_section(summary, 99))
            @test isempty(_Results._read_csv_section(joinpath(root, "absent.csv")))

            _write_text(path, "A,B\n1,2\n")
            @test length(_Results._read_csv_sections(path)) == 1
        end
    end

    @testset "category ordering" begin
        # Lexicographic order would give "10" before "2".
        @test _Results._sort_categories(["10", "2", "1"]) == ["1", "2", "10"]
        @test _Results._sort_categories(["2025-2030", "2020-2025"]) == ["2020-2025", "2025-2030"]
        @test _Results._sort_categories(["Solar", "Coal"]) == ["Coal", "Solar"]
        # Numeric labels sort ahead of non-numeric ones rather than interleaving.
        @test _Results._sort_categories(["Solar", "2"]) == ["2", "Solar"]
    end

    @testset "numeric coercion" begin
        @test _Results._number(1.5) == 1.5
        @test _Results._number(missing) == 0.0
        @test _Results._number("") == 0.0
        @test _Results._number("  ") == 0.0
        @test _Results._number("2.5") == 2.5
        @test _Results._number("n/a") == 0.0
    end

    @testset "javascript escaping" begin
        # A raw newline would terminate the literal and break the page.
        @test _Results._js_string("a\nb") == "\"a\\nb\""
        @test _Results._js_string("a\"b") == "\"a\\\"b\""
        @test _Results._js_string("a\\b") == "\"a\\\\b\""
        # "</script>" must not survive intact inside a script block.
        escaped = _Results._js_string("</script>")
        @test !occursin("</script>", escaped)
        @test occursin("\\u003c", escaped)
        @test _Results._js_value(true) == "true"
        @test _Results._js_value(NaN) == "null"
        @test _Results._js_value(Inf) == "null"
    end

    @testset "period dropdown with unknown active period" begin
        # findfirst returns nothing here; the old code did `nothing - 1`.
        dropdown = _Results._period_dropdown([1, 2], Dict(1 => [1], 2 => [2]), 2, "Title", 99)
        @test occursin("\"active\": 1", dropdown)
    end

    return nothing
end

function test_postprocessing_specs()
    mktempdir() do root
        output_dir = joinpath(root, "output")
        _write_fake_output(output_dir)
        specs = _Results._available_result_plot_specs(output_dir, nothing)
        by_title = Dict(spec.title => spec for spec in specs)

        @testset "generation mix uses weighted annual production" begin
            spec = by_title["Annual Generation by Technology"]
            # Windonshore is summed across NO and SE for 2020-2025: 700.8 + 350.4.
            @test occursin("1051.2", spec.traces[findfirst(t -> occursin("\"name\": \"Wind onshore\"", t), spec.traces)])
            @test occursin("\"2020-2025\", \"2025-2030\"", spec.layout)
        end

        @testset "capacity factor is capacity weighted" begin
            spec = by_title["Capacity Factor by Technology"]
            wind = spec.traces[findfirst(t -> occursin("\"name\": \"Wind onshore\"", t), spec.traces)]
            # (700.8 + 350.4) GWh -> MWh over (200 + 100) MW * 8760 h = 0.4.
            @test occursin("0.4", wind)
        end

        @testset "emissions plot carries the cap" begin
            spec = by_title["CO2 Emissions vs Cap"]
            @test any(t -> occursin("\"name\": \"CO2 cap\"", t), spec.traces)
            @test any(t -> occursin("\"name\": \"scenario1\"", t), spec.traces)
            # Tons converted to Mt.
            @test any(t -> occursin("200.0", t), spec.traces)
        end

        @testset "investment cost splits by asset class" begin
            spec = by_title["Discounted Investment Cost"]
            names = [t for t in spec.traces]
            @test any(t -> occursin("\"name\": \"Generation\"", t), names)
            @test any(t -> occursin("\"name\": \"Storage\"", t), names)
            @test any(t -> occursin("\"name\": \"Transmission\"", t), names)
            # Generation 2020-2025: (1.0e6 + 5.0e5) EUR -> 1.5 MEUR.
            generation = names[findfirst(t -> occursin("\"name\": \"Generation\"", t), names)]
            @test occursin("1.5", generation)
        end

        @testset "scenario series stay separate" begin
            spec = by_title["Average Electricity Price"]
            @test length(spec.traces) == 2
        end

        @testset "empty EuropeSummary yields no spec rather than an error" begin
            bare = joinpath(root, "bare")
            mkpath(bare)
            write(joinpath(bare, "results_output_EuropeSummary.csv"), "Period,Scenario,AvgELPrice_EuroPerMWh\n")
            @test _Results._scenario_series_spec(
                joinpath(bare, "results_output_EuropeSummary.csv"),
                "Empty", :AvgELPrice_EuroPerMWh, "x";
                filename = "empty.html",
            ) === nothing
        end
    end
    return nothing
end

"""
Minimal `results_output_Operational.csv`.

Two nodes, two periods, two scenarios, two seasons of two hours. Sinks are
negative as `src/results.jl` writes them, and every row balances by construction
so `_dispatch_role`'s classification can be asserted against it: generation +
storDischarge + FlowIn + LoadShed + Load + storCharge + FlowOut + LossesFlowIn
sums to zero, and `LossesChargeDischargeBleed_MW` is deliberately non-zero and
outside that sum.
"""
function _write_fake_operational(output_dir)
    header = "Node,Period,Scenario,Season,Hour,AllGen_MW,Load_MW,Net_load_MW," *
        "Gasexisting_MW,GasOCGT_MW,Windonshore_MW,Solar_MW," *
        "storCharge_MW,storDischarge_MW,storEnergyLevel_MWh,LossesChargeDischargeBleed_MW," *
        "FlowOut_MW,FlowIn_MW,LossesFlowIn_MW,LoadShed_MW,Price_EURperMWh,AvgCO2_kgCO2perMWh"

    rows = String[]
    for (node, scale) in (("NO", 1.0), ("SE", 2.0)), period in ("2020-2025", "2025-2030"),
            scenario in ("scenario1", "scenario2"), (season, hours) in (("winter", 1:2), ("summer", 3:4))
        for hour in hours
            # scenario2 is deliberately different so picking the wrong scenario
            # would change every asserted number.
            factor = scale * (scenario == "scenario1" ? 1.0 : 10.0)
            gas_existing = 10.0 * factor
            gas_ocgt = 5.0 * factor
            wind = 20.0 * factor
            solar = hour * factor
            allgen = gas_existing + gas_ocgt + wind + solar
            discharge = 4.0 * factor
            flow_in = 3.0 * factor
            load_shed = 0.0
            charge = -2.0 * factor
            flow_out = -1.0 * factor
            loss_in = -0.5 * factor
            bleed = -0.25 * factor              # excluded from the balance
            load = -(allgen + discharge + flow_in + load_shed + charge + flow_out + loss_in)
            push!(rows, join(
                [
                    node, period, scenario, season, hour, allgen, load, -allgen,
                    gas_existing, gas_ocgt, wind, solar,
                    charge, discharge, 100.0, bleed,
                    flow_out, flow_in, loss_in, load_shed, 30.0 + hour, 200.0,
                ], ","))
        end
    end
    return _write_text(joinpath(output_dir, "results_output_Operational.csv"), header * "\n" * join(rows, "\n") * "\n")
end

function test_postprocessing_dispatch()
    @testset "operational columns are classified" begin
        @test _Results._dispatch_role(:Load_MW) == (:load, "Load")
        @test _Results._dispatch_role(:Price_EURperMWh) == (:price, "Price")
        @test _Results._dispatch_role(:FlowIn_MW) == (:supply, "Import")
        @test _Results._dispatch_role(:FlowOut_MW) == (:sink, "Export")
        @test _Results._dispatch_role(:LossesFlowIn_MW) == (:sink, "Transmission losses")
        # Generation columns fold into the families used everywhere else.
        @test _Results._dispatch_role(:GasOCGT_MW) == (:supply, "Gas")
        @test _Results._dispatch_role(:Windonshore_MW) == (:supply, "Wind onshore")

        # Identities and states must not become bands.
        for column in (:AllGen_MW, :Net_load_MW, :storEnergyLevel_MWh, :AvgCO2_kgCO2perMWh, :Node, :Hour)
            @test first(_Results._dispatch_role(column)) === :skip
        end
        # Already netted into storCharge/storDischarge; stacking it double-counts.
        @test first(_Results._dispatch_role(:LossesChargeDischargeBleed_MW)) === :skip
    end

    @testset "node names survive becoming filenames" begin
        @test _Results._filename_slug("GreatBrit.") == "GreatBrit"
        @test _Results._filename_slug("NO1") == "NO1"
        @test _Results._filename_slug("Sorlige Nordsjo I") == "SorligeNordsjoI"
        @test _Results._filename_slug("../etc") == "etc"
        @test _Results._filename_slug("...") == "node"
    end

    @test isempty(_Results._dispatch_specs(joinpath(mktempdir(), "absent.csv")))

    mktempdir() do root
        output_dir = joinpath(root, "output")
        mkpath(output_dir)
        _write_fake_operational(output_dir)
        csv = joinpath(output_dir, "results_output_Operational.csv")
        data = _Results._read_dispatch_data(csv)

        @testset "one scenario is read, deterministically" begin
            @test data.scenario == "scenario1"
            @test data.nodes == ["NO", "SE"]
            @test data.periods == ["2020-2025", "2025-2030"]
            # scenario2 carries 10x the values; reading it would show here.
            wind = data.values[("NO", "2020-2025", "Wind onshore")]
            @test wind[1] == 20.0
        end

        @testset "generation columns aggregate into families" begin
            # Gasexisting 10 + GasOCGT 5, for node NO (scale 1.0).
            @test data.values[("NO", "2020-2025", "Gas")][1] == 15.0
            # SE is scaled by 2.
            @test data.values[("SE", "2020-2025", "Gas")][1] == 30.0
        end

        @testset "load is drawn as positive demand" begin
            # Stored negated: the CSV holds Load_MW < 0.
            @test data.values[("NO", "2020-2025", "Load")][1] > 0
        end

        @testset "seasons are located at their last hour" begin
            @test data.season_last_hour == Dict("winter" => 2, "summer" => 4)
        end

        @testset "the stack balances every hour" begin
            worst = 0.0
            for node in data.nodes, period in data.periods, hour in data.hours[(node, period)]
                supply = 0.0
                sink = 0.0
                load = 0.0
                for (label, role) in data.roles
                    series = get(data.values, (node, period, label), nothing)
                    series === nothing && continue
                    value = get(series, hour, 0.0)
                    role === :supply && (supply += value)
                    role === :sink && (sink += value)
                    role === :load && (load = value)
                end
                worst = max(worst, abs(supply + sink - load))
            end
            # Would be off by exactly LossesChargeDischargeBleed_MW if the bleed
            # column were stacked.
            @test worst < 1e-9
        end

        @testset "one page per node, one trace group per period" begin
            specs = _Results._dispatch_specs(csv)
            @test length(specs) == 2
            @test [spec.filename for spec in specs] == ["dispatch_NO.html", "dispatch_SE.html"]

            spec = first(specs)
            @test occursin("scenario1", spec.note)
            # Supply and sink bands stack separately, price sits on its own axis.
            @test any(t -> occursin("\"stackgroup\": \"supply\"", t), spec.traces)
            @test any(t -> occursin("\"stackgroup\": \"sink\"", t), spec.traces)
            @test any(t -> occursin("\"yaxis\": \"y2\"", t), spec.traces)
            # Exactly one period's traces are visible at load.
            hidden = count(t -> occursin("\"visible\": false", t), spec.traces)
            @test hidden == length(spec.traces) ÷ 2
            # Both seasons are marked.
            @test occursin("winter", spec.layout)
            @test occursin("summer", spec.layout)
            @test occursin("\"2025-2030\"", spec.layout)
        end
    end

    @testset "oversized raw dumps are skipped, not hung on" begin
        mktempdir() do dir
            small = _write_text(joinpath(dir, "genOperational.csv"), "Period,Generator,genOperational\n1,Nuclear,5.0\n")
            @test _Results._raw_dump_is_plottable(small, "small")
            @test !_Results._raw_dump_is_plottable(joinpath(dir, "absent.csv"), "absent")

            big = joinpath(dir, "big.csv")
            open(big, "w") do io
                write(io, "Period,Generator,genOperational\n")
                # Just over the limit; the guard reads filesize, not the rows.
                write(io, repeat("1,Nuclear,5.0\n", (_Results.RAW_DUMP_MAX_BYTES ÷ 14) + 2))
            end
            @test filesize(big) > _Results.RAW_DUMP_MAX_BYTES
            @test (@test_logs (:warn,) match_mode = :any _Results._raw_dump_is_plottable(big, "big")) == false
        end
    end

    @testset "corridors collapse into capacity bands" begin
        coords = Dict(
            "A" => (lat = 50.0, lon = 5.0), "B" => (lat = 52.0, lon = 6.0),
            "C" => (lat = 54.0, lon = 7.0), "D" => (lat = 56.0, lon = 8.0),
        )
        # Many corridors over few nodes, which is the shape that broke the map:
        # europe_v51 has 190 corridors and produced 190 legend rows.
        pairs = [("A", "B"), ("B", "C"), ("C", "D"), ("A", "D"), ("A", "C"), ("B", "D")]
        corridors = [
            (
                from_node = from, to_node = to,
                capacity = 100.0 * index,
                line_type = isodd(index) ? "HVAC" : "HVDC",
                hover = "$from-$to",
            )
            for (index, (from, to)) in enumerate(repeat(pairs, 5))
        ]
        traces, nodes = _Results._corridor_traces(corridors, coords)
        # 30 corridors must never mean 30 legend rows: at most 2 line types x 4 bands.
        @test length(corridors) == 30
        @test length(traces) <= 8
        @test nodes == Set(["A", "B", "C", "D"])
        # Segments are separated by a JSON null so one trace draws several lines.
        @test any(t -> occursin("null", t), traces)
        # Each corridor's hover text survives the merge.
        @test any(t -> occursin("A-B", t), traces)
        @test any(t -> occursin("A-D", t), traces)

        @testset "a uniform capacity column yields one band, not empty ones" begin
            flat = [
                (from_node = "A", to_node = "B", capacity = 20000.0, line_type = "HVAC", hover = "x"),
                (from_node = "B", to_node = "C", capacity = 20000.0, line_type = "HVAC", hover = "y"),
            ]
            flat_traces, _ = _Results._corridor_traces(flat, coords)
            @test length(flat_traces) == 1
            # The line type alone, not "HVAC " with an empty bracket after it.
            @test occursin("\"name\": \"HVAC\"", flat_traces[1])
        end
    end

    @testset "map is framed on the nodes" begin
        coords = Dict("A" => (lat = 50.0, lon = 5.0), "B" => (lat = 60.0, lon = 15.0))
        bounds = _Results._node_bounds(coords)
        @test bounds.lat[1] < 50.0 && bounds.lat[2] > 60.0
        @test bounds.lon[1] < 5.0 && bounds.lon[2] > 15.0
        @test _Results._node_bounds(Dict{String, NamedTuple{(:lat, :lon), Tuple{Float64, Float64}}}()) === nothing
    end

    @testset "axis units step up only when the numbers demand it" begin
        title = "Expected annual production [GWh]"
        small = Dict(("2020-2025", "Wind") => 700.8, ("2020-2025", "Solar") => 350.4)
        values, unit_title = _Results._rescale_unit(small, title, key -> key[1])
        @test unit_title == title
        @test values[("2020-2025", "Wind")] == 700.8

        # Stacked column of 8e6 GWh: the axis Plotly would label "8M".
        large = Dict(("2020-2025", "Wind") => 5.0e6, ("2020-2025", "Solar") => 3.0e6)
        values, unit_title = _Results._rescale_unit(large, title, key -> key[1])
        @test unit_title == "Expected annual production [TWh]"
        @test values[("2020-2025", "Wind")] == 5000.0

        # An unrecognised unit is left alone rather than silently mis-scaled.
        odd = Dict(("x", "y") => 1.0e9)
        _, odd_title = _Results._rescale_unit(odd, "Capacity factor [-]", key -> key[1])
        @test odd_title == "Capacity factor [-]"
    end

    @testset "label dropdown with unknown active label" begin
        # The string-labelled sibling of the period dropdown, same nothing - 1 trap.
        dropdown = _Results._label_dropdown(["a", "b"], Dict("a" => [1], "b" => [2]), 2, "T", "zzz")
        @test occursin("\"active\": 1", dropdown)
    end

    return nothing
end

function test_postprocessing_dashboard()
    mktempdir() do root
        _write_fake_output(joinpath(root, "output"))
        dashboard = _Results.write_result_plots(root)

        @test isfile(dashboard)
        html = read(dashboard, String)
        @test occursin("Annual Generation by Technology", html)
        @test occursin("CO2 Emissions vs Cap", html)
        @test occursin("plotly-missing", html)   # offline fallback banner
        @test occursin("cdn.plot.ly", html)      # no vendored copy was supplied

        # Standalone pages are written alongside the dashboard.
        @test isfile(joinpath(root, "Plots", "generation_mix.html"))

        @testset "dispatch pages are linked, not embedded" begin
            _write_fake_operational(joinpath(root, "output"))
            dashboard = _Results.write_result_plots(root)
            html = read(dashboard, String)

            @test isfile(joinpath(root, "Plots", "dispatch_NO.html"))
            @test isfile(joinpath(root, "Plots", "dispatch_SE.html"))
            @test occursin("href=\"dispatch_NO.html\"", html)
            # Inlining one page per node would make dashboard.html unopenable on
            # a 49-node dataset, so the traces must stay out of it.
            @test !occursin("\"stackgroup\"", html)
        end

        @testset "vendored plotly is referenced relatively" begin
            vendored = joinpath(root, "plotly.min.js")
            write(vendored, "/* stub */")
            dashboard = _Results.write_result_plots(root; plotly_js = vendored)
            html = read(dashboard, String)
            @test occursin("src=\"plotly.min.js\"", html)
            @test !occursin("cdn.plot.ly", html)
            @test isfile(joinpath(root, "Plots", "plotly.min.js"))
        end

        @testset "missing output directory is reported clearly" begin
            mktempdir() do empty_root
                @test_throws ArgumentError _Results.write_result_plots(empty_root)
            end
        end
    end
    return nothing
end
