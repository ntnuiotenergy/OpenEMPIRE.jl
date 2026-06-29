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
