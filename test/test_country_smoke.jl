# NUTS2 country-constraint smoke test.
#
# A minimal, feasible-by-construction 2-country / 4-node CSV dataset that
# exercises all three country-level generator capacity constraints
# (max_inv_tech_country, min_inv_tech_country, max_inst_tech_country; see
# create_generator_constraints in src/model_definition.jl). Reuses the
# _write_csv helper from test_csv.jl (included earlier in runtests.jl).
#
# Countries: Alpha = {A1, A2}, Beta = {B1, B2}, Gamma = {Gamma}. Beta carries
# no country-level constraint rows, so it acts as a data-driven contrast group.
# Gamma is deliberately represented by one aggregate national node, exercising
# mixed spatial resolution alongside the disaggregated Alpha/Beta countries.
#
# Alpha demand = 15 MW (A1=10, A2=5); existing gas = 10 MW (A1=6, A2=4);
# deficit = 5 MW. wind is strictly more expensive per MW than gas (capital
# 400 vs 100), so cost-minimization only ever builds the mandated
# renewable floor and never more. With the baseline country rows
# (genMaxBuiltCapCountry=2, genMinBuiltCapCountry=3,
# genMaxInstalledCapCountry=12), the unique cost-minimal AGGREGATE solution
# is: new wind = 3 MW (MinBuild floor), new gas = 5 - 3 = 2 MW (closes the
# remaining deficit), installed gas = 10 + 2 = 12 MW. All three country caps
# hold with equality. Per-node investment split is not unique (genCapitalCost
# is priced per generator, not per node), so only country aggregates are
# asserted, per the smoke-test brief.
#
# Beta demand = 12 MW (B1=8, B2=4) is covered entirely by existing gas
# (B1=10, B2=6): zero investment, zero load shedding, unconstrained.

function _write_country_smoke_csv_dataset(
        root;
        name = "country_smoke",
        include_country_sets = true,
        include_max_build = true,
        max_build_value = 2.0,
        include_min_build = true,
        min_build_value = 3.0,
        include_max_installed = true,
        max_installed_value = 12.0,
    )
    dataset = joinpath(root, name)

    _write_csv(joinpath(dataset, "Sets", "Generator.csv"), "Generator\ngas\nwind\n")
    _write_csv(joinpath(dataset, "Sets", "ThermalGenerators.csv"), "ThermalGenerators\ngas\n")
    _write_csv(joinpath(dataset, "Sets", "HydroGenerator.csv"), "HydroGenerator\n")
    _write_csv(joinpath(dataset, "Sets", "RegHydroGenerator.csv"), "RegHydroGenerator\n")
    _write_csv(joinpath(dataset, "Sets", "Storage.csv"), "Storage\n")
    _write_csv(joinpath(dataset, "Sets", "DependentStorage.csv"), "DependentStorage\n")
    _write_csv(joinpath(dataset, "Sets", "Technology.csv"), "Technology\nthermal\nrenewable\n")
    _write_csv(joinpath(dataset, "Sets", "Node.csv"), "Node\nA1\nA2\nB1\nB2\nGamma\n")
    if include_country_sets
        _write_csv(joinpath(dataset, "Sets", "Countries.csv"), "Country\nAlpha\nBeta\nGamma\n")
        _write_csv(
            joinpath(dataset, "Sets", "NodesOfCountry.csv"),
            "Country,Node\nAlpha,A1\nAlpha,A2\nBeta,B1\nBeta,B2\nGamma,Gamma\n",
        )
    end
    _write_csv(joinpath(dataset, "Sets", "DirectionalLink.csv"), "NodeFrom,NodeTo\nA1,B1\nB1,A1\n")
    _write_csv(joinpath(dataset, "Sets", "TransmissionType.csv"), "TransmissionType\nHVDC\n")
    _write_csv(
        joinpath(dataset, "Sets", "TransmissionTypeOfDirectionalLink.csv"),
        "NodeFrom,NodeTo,TransmissionType\nA1,B1,HVDC\nB1,A1,HVDC\n",
    )
    _write_csv(
        joinpath(dataset, "Sets", "GeneratorsOfTechnology.csv"),
        "Technology,Generator\nthermal,gas\nrenewable,wind\n",
    )
    _write_csv(
        joinpath(dataset, "Sets", "GeneratorsOfNode.csv"),
        "Node,Generator\nA1,gas\nA2,gas\nB1,gas\nB2,gas\nGamma,gas\nA1,wind\nA2,wind\n",
    )
    _write_csv(joinpath(dataset, "Sets", "StoragesOfNode.csv"), "Node,Storage\n")

    # gas is strictly cheaper per MW than wind, so cost-minimization never
    # builds wind beyond the mandated renewable floor (see min_inv_tech_country).
    _write_csv(joinpath(dataset, "Generator", "genCapitalCost.csv"), "GeneratorTechnology,Period,Value\ngas,1,100\nwind,1,1000000\n")
    _write_csv(joinpath(dataset, "Generator", "genFixedOMCost.csv"), "GeneratorTechnology,Period,Value\ngas,1,10\nwind,1,20\n")
    _write_csv(joinpath(dataset, "Generator", "genVariableOMCost.csv"), "Generator,Value\ngas,5\nwind,0\n")
    _write_csv(joinpath(dataset, "Generator", "genFuelCost.csv"), "GeneratorTechnology,Period,Value\ngas,1,8\nwind,1,0\n")
    _write_csv(joinpath(dataset, "Generator", "CCSCostTSVariable.csv"), "Period,Value\n1,0\n")
    _write_csv(joinpath(dataset, "Generator", "genEfficiency.csv"), "GeneratorTechnology,Period,Value\ngas,1,0.5\nwind,1,1\n")
    _write_csv(joinpath(dataset, "Generator", "genRefInitCap.csv"), "Node,Generator,Value\n")
    _write_csv(joinpath(dataset, "Generator", "genScaleInitCap.csv"), "GeneratorTechnology,Period,Value\n")
    _write_csv(
        joinpath(dataset, "Generator", "genInitCap.csv"),
        "Node,Generator,Period,Value\nA1,gas,1,6\nA2,gas,1,4\nB1,gas,1,10\nB2,gas,1,6\nGamma,gas,1,8\n",
    )
    _write_csv(
        joinpath(dataset, "Generator", "genMaxBuiltCap.csv"),
        "Node,Technology,Period,Value\nA1,thermal,1,1000\nA2,thermal,1,1000\nB1,thermal,1,1000\nB2,thermal,1,1000\nGamma,thermal,1,1000\n" *
        "A1,renewable,1,1000\nA2,renewable,1,1000\n",
    )
    # Every (node, technology) pair with a generator must appear here: the
    # per-pair default (DEFAULT_GEN_MAX_INST_CAP_RAW = 0.0, src/empire_structs.jl)
    # would otherwise force existing capacity to <= 0 and make the model
    # infeasible (see max_inst_tech in src/model_definition.jl).
    _write_csv(
        joinpath(dataset, "Generator", "genMaxInstalledCapRaw.csv"),
        "Node,Technology,Value\nA1,thermal,1000\nA2,thermal,1000\nB1,thermal,1000\nB2,thermal,1000\nGamma,thermal,1000\n" *
        "A1,renewable,1000\nA2,renewable,1000\n",
    )
    if include_max_build
        _write_csv(
            joinpath(dataset, "Generator", "genMaxBuiltCapCountry.csv"),
            "Country,GeneratorTechnology,Period,generatorMaxBuildCapacity_in_MW\nAlpha,thermal,1,$(max_build_value)\n",
        )
    end
    if include_min_build
        _write_csv(
            joinpath(dataset, "Generator", "genMinBuiltCapCountry.csv"),
            "Country,GeneratorTechnology,Period,generatorMinBuildCapacity_in_MW\nAlpha,renewable,1,$(min_build_value)\n",
        )
    end
    if include_max_installed
        _write_csv(
            joinpath(dataset, "Generator", "genMaxInstalledCapCountry.csv"),
            "Country,GeneratorTechnology,generatorMaxInstallCapacity__in_MW\nAlpha,thermal,$(max_installed_value)\n",
        )
    end
    _write_csv(joinpath(dataset, "Generator", "genRampUpCap.csv"), "Generator,Value\ngas,1\nwind,1\n")
    _write_csv(joinpath(dataset, "Generator", "genCapAvailTypeRaw.csv"), "Generator,Value\ngas,1\nwind,1\n")
    _write_csv(joinpath(dataset, "Generator", "genCO2TypeFactor.csv"), "Generator,Value\ngas,0\nwind,0\n")
    _write_csv(joinpath(dataset, "Generator", "genLifetime.csv"), "Generator,Value\ngas,30\nwind,25\n")

    _write_csv(joinpath(dataset, "Transmission", "transmissionInitCap.csv"), "From,To,Period,Value\nA1,B1,1,0\nB1,A1,1,0\n")
    _write_csv(joinpath(dataset, "Transmission", "transmissionMaxBuiltCap.csv"), "From,To,Period,Value\nA1,B1,1,0\nB1,A1,1,0\n")
    _write_csv(joinpath(dataset, "Transmission", "transmissionMaxInstalledCapRaw.csv"), "From,To,Period,Value\nA1,B1,1,0\nB1,A1,1,0\n")
    _write_csv(joinpath(dataset, "Transmission", "transmissionLength.csv"), "From,To,Value\nA1,B1,10\nB1,A1,10\n")
    _write_csv(joinpath(dataset, "Transmission", "transmissionTypeCapitalCost.csv"), "Type,Period,Value\nHVDC,1,1\n")
    _write_csv(joinpath(dataset, "Transmission", "transmissionTypeFixedOMCost.csv"), "Type,Period,Value\nHVDC,1,0\n")
    _write_csv(joinpath(dataset, "Transmission", "lineEfficiency.csv"), "From,To,Value\nA1,B1,0.95\nB1,A1,0.95\n")
    _write_csv(joinpath(dataset, "Transmission", "transmissionLifetime.csv"), "From,To,Value\nA1,B1,40\nB1,A1,40\n")

    # No storage in this dataset; every Storage/*.csv is still a required file
    # (src/read_csv.jl), so each is written header-only.
    _write_csv(joinpath(dataset, "Storage", "storageBleedEff.csv"), "Storage,Value\n")
    _write_csv(joinpath(dataset, "Storage", "storageChargeEff.csv"), "Storage,Value\n")
    _write_csv(joinpath(dataset, "Storage", "storageDischargeEff.csv"), "Storage,Value\n")
    _write_csv(joinpath(dataset, "Storage", "storagePowToEnergy.csv"), "Storage,Value\n")
    _write_csv(joinpath(dataset, "Storage", "storENCapitalCost.csv"), "Storage,Period,Value\n")
    _write_csv(joinpath(dataset, "Storage", "storENFixedOMCost.csv"), "Storage,Period,Value\n")
    _write_csv(joinpath(dataset, "Storage", "storENInitCap.csv"), "Node,Storage,Period,Value\n")
    _write_csv(joinpath(dataset, "Storage", "storENMaxBuiltCap.csv"), "Node,Storage,Period,Value\n")
    _write_csv(joinpath(dataset, "Storage", "storENMaxInstalledCapRaw.csv"), "Node,Storage,Value\n")
    _write_csv(joinpath(dataset, "Storage", "storOperationalInit.csv"), "Storage,Value\n")
    _write_csv(joinpath(dataset, "Storage", "storPWCapitalCost.csv"), "Storage,Period,Value\n")
    _write_csv(joinpath(dataset, "Storage", "storPWFixedOMCost.csv"), "Storage,Period,Value\n")
    _write_csv(joinpath(dataset, "Storage", "storPWInitCap.csv"), "Node,Storage,Period,Value\n")
    _write_csv(joinpath(dataset, "Storage", "storPWMaxBuiltCap.csv"), "Node,Storage,Period,Value\n")
    _write_csv(joinpath(dataset, "Storage", "storPWMaxInstalledCapRaw.csv"), "Node,Storage,Value\n")
    _write_csv(joinpath(dataset, "Storage", "storageLifetime.csv"), "Storage,Value\n")

    _write_csv(
        joinpath(dataset, "Node", "nodeLostLoadCost.csv"),
        "Node,Period,Value\nA1,1,22000\nA2,1,22000\nB1,1,22000\nB2,1,22000\nGamma,1,22000\n",
    )
    _write_csv(
        joinpath(dataset, "Node", "sloadAnnualDemand.csv"),
        "Node,Period,Value\nA1,1,87600\nA2,1,43800\nB1,1,70080\nB2,1,35040\nGamma,1,52560\n",
    )
    _write_csv(joinpath(dataset, "Node", "maxHydroNode.csv"), "Node,Value\nA1,0\nA2,0\nB1,0\nB2,0\nGamma,0\n")

    _write_csv(joinpath(dataset, "General", "CO2cap.csv"), "Period,Value\n1,100\n")
    _write_csv(joinpath(dataset, "General", "CO2price.csv"), "Period,Value\n1,0\n")

    # Already-generated scenario format (use_scenario_generation: false).
    # Single hour, single scenario: sloadRaw is a flat shape of 1.0; the
    # actual hourly demand comes from sloadAnnualDemand / 8760 via
    # preprocess_stoch_load (src/utils.jl).
    _write_csv(
        joinpath(dataset, "ScenarioData", "sloadRaw.csv"),
        "Node,Operationalhour,Scenario,Period,ElectricLoadRaw_in_MW\n" *
        "A1,1,scenario1,1,1.0\nA2,1,scenario1,1,1.0\nB1,1,scenario1,1,1.0\nB2,1,scenario1,1,1.0\nGamma,1,scenario1,1,1.0\n",
    )
    _write_csv(
        joinpath(dataset, "ScenarioData", "maxRegHydroGenRaw.csv"),
        "Node,Period,Season,Operationalhour,Scenario,HydroGeneratorMaxSeasonalProduction\n",
    )
    _write_csv(
        joinpath(dataset, "ScenarioData", "genCapAvailStochRaw.csv"),
        "Node,IntermitentGenerators,Operationalhour,Scenario,Period,GeneratorStochasticAvailabilityRaw\n",
    )

    return dataset
end

function _country_smoke_config_file()
    return joinpath(pkgdir(OpenEMPIRE), "config", "testrun_country_smoke.yaml")
end

function _solve_country_smoke(root; dataset_kwargs...)
    dataset = _write_country_smoke_csv_dataset(root; dataset_kwargs...)
    emp, periods, sets, params = OpenEMPIRE.create_model(
        _country_smoke_config_file(),
        dataset;
        optimizer = HiGHS.Optimizer,
        input_format = :csv,
        scenario_rng = MersenneTwister(1),
    )
    JuMP.set_silent(emp)
    optimize!(emp)
    @assert JuMP.is_solved_and_feasible(emp) "Country smoke dataset failed to solve: $(JuMP.termination_status(emp))"
    return emp, periods, sets, params
end

_total_load_shed(emp, sets, periods) =
    sum(JuMP.value(emp[:loadShed][n, t]) for n in OpenEMPIRE.nodes(sets) for t in periods)

function _country_tech_investment(emp, sets, sp, country, technology)
    invCap = emp[:genInvCap]
    return sum(
        JuMP.value(invCap[n, g, sp])
        for n in OpenEMPIRE.nodes_of_country(sets, country)
        for g in OpenEMPIRE.generators_tech(sets, n, technology);
        init = 0.0,
    )
end

function _country_tech_installed(emp, sets, sp, country, technology)
    installedCap = emp[:genInstalledCap]
    return sum(
        JuMP.value(installedCap[n, g, sp])
        for n in OpenEMPIRE.nodes_of_country(sets, country)
        for g in OpenEMPIRE.generators_tech(sets, n, technology);
        init = 0.0,
    )
end

function test_country_smoke_baseline_solve()
    mktempdir() do root
        emp, periods, sets, params = _solve_country_smoke(root; name = "country_smoke_baseline")
        sp = first(strat_periods(periods))

        @test length(emp[:max_inv_tech_country]) == 1
        @test length(emp[:min_inv_tech_country]) == 1
        @test length(emp[:max_inst_tech_country]) == 1

        @test OpenEMPIRE.country_max_inst_cap(params, "Alpha", "thermal", sp) == 12.0
        @test OpenEMPIRE.country_max_build_cap(params, "Beta", "thermal", sp) == OpenEMPIRE.DEFAULT_GEN_MAX_BUILD_CAP

        @test _total_load_shed(emp, sets, periods) ≈ 0.0 atol = 1e-6

        @test _country_tech_investment(emp, sets, sp, "Alpha", "thermal") ≈ 2.0 atol = 1e-6
        @test _country_tech_installed(emp, sets, sp, "Alpha", "thermal") ≈ 12.0 atol = 1e-6
        @test _country_tech_investment(emp, sets, sp, "Alpha", "renewable") ≈ 3.0 atol = 1e-6

        @test _country_tech_investment(emp, sets, sp, "Beta", "thermal") ≈ 0.0 atol = 1e-6

        # Mixed-resolution check: Gamma is a country represented by one
        # aggregate national node rather than multiple subnational nodes.
        @test collect(OpenEMPIRE.nodes_of_country(sets, "Gamma")) == ["Gamma"]
        @test _country_tech_investment(emp, sets, sp, "Gamma", "thermal") ≈ 0.0 atol = 1e-6
    end
end

# Isolates min_inv_tech_country: with MaxBuild/MaxInstalled country rows
# absent (so they never bind), removing the MinBuild floor must drop
# renewable investment to 0 -- the unconstrained cost-minimal choice, since
# wind is strictly more expensive than gas.
function test_country_smoke_minbuild_forces_investment()
    mktempdir() do root
        emp_on, periods_on, sets_on, _ = _solve_country_smoke(
            root;
            name = "country_smoke_minbuild_on",
            include_max_build = false,
            include_max_installed = false,
            include_min_build = true,
        )
        sp_on = first(strat_periods(periods_on))
        @test _country_tech_investment(emp_on, sets_on, sp_on, "Alpha", "renewable") ≈ 3.0 atol = 1e-6
        @test _country_tech_investment(emp_on, sets_on, sp_on, "Alpha", "thermal") ≈ 2.0 atol = 1e-6

        emp_off, periods_off, sets_off, _ = _solve_country_smoke(
            root;
            name = "country_smoke_minbuild_off",
            include_max_build = false,
            include_max_installed = false,
            include_min_build = false,
        )
        sp_off = first(strat_periods(periods_off))
        @test isempty(emp_off[:min_inv_tech_country])
        @test _country_tech_investment(emp_off, sets_off, sp_off, "Alpha", "renewable") ≈ 0.0 atol = 1e-6
        @test _country_tech_investment(emp_off, sets_off, sp_off, "Alpha", "thermal") ≈ 5.0 atol = 1e-6
    end
end

# Isolates max_inv_tech_country: with MaxInstalled absent (so it never
# binds) and the MinBuild floor fixed at 3 MW, tightening MaxBuild below the
# natural 2 MW gas requirement forces cost-minimization to substitute costlier
# wind for the missing gas, strictly raising the objective.
function test_country_smoke_maxbuild_limits_investment()
    mktempdir() do root
        emp_loose, periods_loose, sets_loose, _ = _solve_country_smoke(
            root;
            name = "country_smoke_maxbuild_loose",
            include_max_build = true,
            max_build_value = 100.0,
            include_max_installed = false,
            include_min_build = true,
        )
        sp_loose = first(strat_periods(periods_loose))
        @test _country_tech_investment(emp_loose, sets_loose, sp_loose, "Alpha", "thermal") ≈ 2.0 atol = 1e-6
        @test _country_tech_investment(emp_loose, sets_loose, sp_loose, "Alpha", "renewable") ≈ 3.0 atol = 1e-6

        emp_tight, periods_tight, sets_tight, _ = _solve_country_smoke(
            root;
            name = "country_smoke_maxbuild_tight",
            include_max_build = true,
            max_build_value = 1.0,
            include_max_installed = false,
            include_min_build = true,
        )
        sp_tight = first(strat_periods(periods_tight))
        @test _country_tech_investment(emp_tight, sets_tight, sp_tight, "Alpha", "thermal") ≈ 1.0 atol = 1e-6
        @test _country_tech_investment(emp_tight, sets_tight, sp_tight, "Alpha", "renewable") ≈ 4.0 atol = 1e-6
        @test _total_load_shed(emp_tight, sets_tight, periods_tight) ≈ 0.0 atol = 1e-6

        @test JuMP.objective_value(emp_tight) > JuMP.objective_value(emp_loose)
    end
end

# Isolates max_inst_tech_country: with MaxBuild absent (so it never binds)
# and the MinBuild floor fixed at 3 MW, tightening MaxInstalled below the
# natural 12 MW total forces less new gas and more substitute wind, strictly
# raising the objective -- independent of, and not explained by, MaxBuild.
function test_country_smoke_maxinstalled_limits_capacity()
    mktempdir() do root
        emp_loose, periods_loose, sets_loose, _ = _solve_country_smoke(
            root;
            name = "country_smoke_maxinstalled_loose",
            include_max_build = false,
            include_max_installed = true,
            max_installed_value = 100.0,
            include_min_build = true,
        )
        sp_loose = first(strat_periods(periods_loose))
        @test _country_tech_installed(emp_loose, sets_loose, sp_loose, "Alpha", "thermal") ≈ 12.0 atol = 1e-6

        emp_tight, periods_tight, sets_tight, _ = _solve_country_smoke(
            root;
            name = "country_smoke_maxinstalled_tight",
            include_max_build = false,
            include_max_installed = true,
            max_installed_value = 11.0,
            include_min_build = true,
        )
        sp_tight = first(strat_periods(periods_tight))
        @test _country_tech_installed(emp_tight, sets_tight, sp_tight, "Alpha", "thermal") ≈ 11.0 atol = 1e-6
        @test _country_tech_investment(emp_tight, sets_tight, sp_tight, "Alpha", "renewable") ≈ 4.0 atol = 1e-6
        @test _total_load_shed(emp_tight, sets_tight, periods_tight) ≈ 0.0 atol = 1e-6

        @test JuMP.objective_value(emp_tight) > JuMP.objective_value(emp_loose)
    end
end

# Regression: without Sets/Countries.csv and Sets/NodesOfCountry.csv (and
# therefore without any of the three country CSVs), the model must build
# exactly as it did before NUTS2 support -- no country-level constraints at
# all -- mirroring test_country_generator_constraints_are_data_driven but
# exercised through the full CSV + create_model path.
function test_country_smoke_non_nuts2_regression()
    mktempdir() do root
        emp, _, _, _ = _solve_country_smoke(
            root;
            name = "country_smoke_no_countries",
            include_country_sets = false,
            include_max_build = false,
            include_min_build = false,
            include_max_installed = false,
        )
        @test isempty(emp[:max_inv_tech_country])
        @test isempty(emp[:min_inv_tech_country])
        @test isempty(emp[:max_inst_tech_country])
    end
end
