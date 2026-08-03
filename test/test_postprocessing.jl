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
