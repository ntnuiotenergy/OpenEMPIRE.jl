using JuMP
using OpenEMPIRE
using Test
using TimeStruct

function _write_oos_csv(path, content)
    mkpath(dirname(path))
    write(path, content)
    return path
end

function test_fix_investments_from_results()
    sets = OpenEMPIRE.EmpireSets(
        Generator = ["Solar"],
        Storage = ["battery"],
        Technology = ["Solar"],
        Node = ["A", "B"],
        DirectionalLink = [("A", "B"), ("B", "A")],
        TransmissionType = ["HVDC"],
        TransmissionTypeOfDirectionalLink = [("A", "B", "HVDC"), ("B", "A", "HVDC")],
        GeneratorsOfTechnology = [("Solar", "Solar")],
        GeneratorsOfNode = [("A", "Solar")],
        StoragesOfNode = [("A", "battery")],
    )
    periods = OpenEMPIRE.create_timestruct(1, 5, 1, 2, 0, 0, 1)
    sp = first(strat_periods(periods))

    model = JuMP.Model()
    OpenEMPIRE.create_variables(model, sets, periods)

    mktempdir() do result_dir
        output_dir = joinpath(result_dir, "Output")

        _write_oos_csv(joinpath(output_dir, "genInvCap.csv"), "Node,Generator,Period,genInvCap\nA,Solar,1,3.5\n")
        _write_oos_csv(joinpath(output_dir, "transmissionInvCap.csv"), "FromNode,ToNode,Period,transmissionInvCap\nA,B,1,4.5\n")
        _write_oos_csv(joinpath(output_dir, "storPWInvCap.csv"), "Node,Storage,Period,storPWInvCap\nA,battery,1,5.5\n")
        _write_oos_csv(joinpath(output_dir, "storENInvCap.csv"), "Node,Storage,Period,storENInvCap\nA,battery,1,6.5\n")
        _write_oos_csv(joinpath(output_dir, "genInstalledCap.csv"), "Node,Generator,Period,genInstalledCap\nA,Solar,1,7.5\n")
        _write_oos_csv(joinpath(output_dir, "transmissionInstalledCap.csv"), "FromNode,ToNode,Period,transmissionInstalledCap\nA,B,1,8.5\n")
        _write_oos_csv(joinpath(output_dir, "storPWInstalledCap.csv"), "Node,Storage,Period,storPWInstalledCap\nA,battery,1,9.5\n")
        _write_oos_csv(joinpath(output_dir, "storENInstalledCap.csv"), "Node,Storage,Period,storENInstalledCap\nA,battery,1,10.5\n")

        OpenEMPIRE.fix_investments_from_results!(model, sets, periods, result_dir)
    end

    @test JuMP.is_fixed(model[:genInvCap]["A", "Solar", sp])
    @test JuMP.fix_value(model[:genInvCap]["A", "Solar", sp]) == 3.5
    @test JuMP.is_fixed(model[:transmissionInvCap]["A", "B", sp])
    @test JuMP.fix_value(model[:transmissionInvCap]["A", "B", sp]) == 4.5
    @test JuMP.is_fixed(model[:storPWInvCap]["A", "battery", sp])
    @test JuMP.fix_value(model[:storPWInvCap]["A", "battery", sp]) == 5.5
    @test JuMP.is_fixed(model[:storENInvCap]["A", "battery", sp])
    @test JuMP.fix_value(model[:storENInvCap]["A", "battery", sp]) == 6.5

    @test JuMP.is_fixed(model[:genInstalledCap]["A", "Solar", sp])
    @test JuMP.fix_value(model[:genInstalledCap]["A", "Solar", sp]) == 7.5
    @test JuMP.is_fixed(model[:transmissionInstalledCap]["A", "B", sp])
    @test JuMP.fix_value(model[:transmissionInstalledCap]["A", "B", sp]) == 8.5
    @test JuMP.is_fixed(model[:storPWInstalledCap]["A", "battery", sp])
    @test JuMP.fix_value(model[:storPWInstalledCap]["A", "battery", sp]) == 9.5
    @test JuMP.is_fixed(model[:storENInstalledCap]["A", "battery", sp])
    @test JuMP.fix_value(model[:storENInstalledCap]["A", "battery", sp]) == 10.5
end

function _oos_test_sets_and_periods()
    sets = OpenEMPIRE.EmpireSets(
        Generator = ["Solar"],
        Storage = ["battery"],
        Technology = ["Solar"],
        Node = ["A", "B"],
        DirectionalLink = [("A", "B"), ("B", "A")],
        TransmissionType = ["HVDC"],
        TransmissionTypeOfDirectionalLink = [
            ("A", "B", "HVDC"),
            ("B", "A", "HVDC"),
        ],
        GeneratorsOfTechnology = [("Solar", "Solar")],
        GeneratorsOfNode = [("A", "Solar")],
        StoragesOfNode = [("A", "battery")],
    )
    periods = OpenEMPIRE.create_timestruct(1, 5, 1, 2, 0, 0, 1)
    return sets, periods
end

function _write_investment_csvs(
    output_dir;
    include_installed = true,
    extra_generator = false,
)
    generator_rows = extra_generator ?
                     "A,Solar,1,3.5\nB,Solar,1,1.0\n" :
                     "A,Solar,1,3.5\n"
    _write_oos_csv(
        joinpath(output_dir, "genInvCap.csv"),
        "Node,Generator,Period,genInvCap\n$generator_rows",
    )
    _write_oos_csv(
        joinpath(output_dir, "transmisionInvCap.csv"),
        "FromNode,ToNode,Period,transmisionInvCap\nA,B,1,4.5\n",
    )
    _write_oos_csv(
        joinpath(output_dir, "storPWInvCap.csv"),
        "Node,Storage,Period,storPWInvCap\nA,battery,1,5.5\n",
    )
    _write_oos_csv(
        joinpath(output_dir, "storENInvCap.csv"),
        "Node,Storage,Period,storENInvCap\nA,battery,1,6.5\n",
    )

    include_installed || return output_dir

    _write_oos_csv(
        joinpath(output_dir, "genInstalledCap.csv"),
        "Node,Generator,Period,genInstalledCap\nA,Solar,1,7.5\n",
    )
    _write_oos_csv(
        joinpath(output_dir, "transmissionInstalledCap.csv"),
        "FromNode,ToNode,Period,transmissionInstalledCap\nA,B,1,8.5\n",
    )
    _write_oos_csv(
        joinpath(output_dir, "storPWInstalledCap.csv"),
        "Node,Storage,Period,storPWInstalledCap\nA,battery,1,9.5\n",
    )
    _write_oos_csv(
        joinpath(output_dir, "storENInstalledCap.csv"),
        "Node,Storage,Period,storENInstalledCap\nA,battery,1,10.5\n",
    )
    return output_dir
end

function test_fix_only_investment_capacities()
    sets, periods = _oos_test_sets_and_periods()
    strategic_period = first(strat_periods(periods))
    model = JuMP.Model()
    OpenEMPIRE.create_variables(model, sets, periods)

    mktempdir() do result_dir
        _write_investment_csvs(
            joinpath(result_dir, "output");
            include_installed = false,
        )
        OpenEMPIRE.fix_investments_from_results!(
            model,
            sets,
            periods,
            result_dir;
            fix_installed_capacities = false,
        )
    end

    @test JuMP.is_fixed(model[:genInvCap]["A", "Solar", strategic_period])
    @test !JuMP.is_fixed(model[:genInstalledCap]["A", "Solar", strategic_period])
    @test !JuMP.is_fixed(
        model[:transmissionInstalledCap]["A", "B", strategic_period],
    )
    @test !JuMP.is_fixed(model[:storPWInstalledCap]["A", "battery", strategic_period])
    @test !JuMP.is_fixed(model[:storENInstalledCap]["A", "battery", strategic_period])
end

function test_fixed_investment_key_validation()
    sets, periods = _oos_test_sets_and_periods()

    mktempdir() do result_dir
        _write_investment_csvs(
            joinpath(result_dir, "output");
            include_installed = false,
            extra_generator = true,
        )
        model = JuMP.Model()
        OpenEMPIRE.create_variables(model, sets, periods)
        @test_throws ArgumentError OpenEMPIRE.fix_investments_from_results!(
            model,
            sets,
            periods,
            result_dir;
            fix_installed_capacities = false,
        )
    end

    mktempdir() do result_dir
        output_dir = _write_investment_csvs(
            joinpath(result_dir, "output");
            include_installed = false,
        )
        write(
            joinpath(output_dir, "genInvCap.csv"),
            "Node,Generator,Period,genInvCap\n",
        )
        model = JuMP.Model()
        OpenEMPIRE.create_variables(model, sets, periods)
        @test_throws ArgumentError OpenEMPIRE.fix_investments_from_results!(
            model,
            sets,
            periods,
            result_dir;
            fix_installed_capacities = false,
        )
    end
end

function test_oos_omits_investment_only_constraints()
    sets, periods = _oos_test_sets_and_periods()
    params = OpenEMPIRE.EmpireParams(genCapAvailType = Dict("Solar" => 1.0))

    mktempdir() do result_dir
        _write_investment_csvs(joinpath(result_dir, "output"))

        investment_model = JuMP.Model(HiGHS.Optimizer)
        JuMP.set_silent(investment_model)
        OpenEMPIRE.create_variables(investment_model, sets, periods)
        OpenEMPIRE.create_constraints(investment_model, sets, params, periods)
        OpenEMPIRE.fix_investments_from_results!(
            investment_model,
            sets,
            periods,
            result_dir,
        )
        @objective(investment_model, Min, 0)
        optimize!(investment_model)
        @test JuMP.termination_status(investment_model) == JuMP.MOI.INFEASIBLE

        oos_model = JuMP.Model(HiGHS.Optimizer)
        JuMP.set_silent(oos_model)
        OpenEMPIRE.create_variables(oos_model, sets, periods)
        OpenEMPIRE.create_constraints(
            oos_model,
            sets,
            params,
            periods;
            include_investment_constraints = false,
        )
        OpenEMPIRE.fix_investments_from_results!(oos_model, sets, periods, result_dir)
        @objective(oos_model, Min, 0)
        optimize!(oos_model)

        @test JuMP.is_solved_and_feasible(oos_model)
        object_names = JuMP.object_dictionary(oos_model)
        for operational_family in (
            :flow_balance,
            :gen_max_prod,
            :storage_bal,
            :trans_cap,
        )
            @test haskey(object_names, operational_family)
        end
        for investment_family in (
            :installed_cap_gen,
            :max_inv_tech,
            :max_inst_tech,
            :storage_installed_cap_en,
            :storage_installed_cap_pow,
            :storage_max_inv_pow,
            :storage_max_inv_en,
            :storage_max_inst_pow,
            :storage_max_inst_en,
            :storage_couple_pow_en,
            :trans_track_cap,
            :trans_max_capacity,
            :trans_installed_cap,
        )
            @test !haskey(object_names, investment_family)
        end
    end
end
