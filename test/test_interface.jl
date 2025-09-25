function test_interface()
    using OpenEMPIRE
    using JuMP
    using Test
    using HiGHS

    config_file = "data/testrun.yaml"
    data_folder = "data"

    emp, periods, sets, params = OpenEMPIRE.create_model(config_file, data_folder)
    set_optimizer(emp, HiGHS.Optimizer)
    optimize!(emp)

    prod = Containers.rowtable(value, emp[:genOperational]; header = [:Node, :Generator, :Time, :Production])
    prod = filter(r -> r.Production > 0.0, prod)

    storDischarge = Containers.rowtable(value, emp[:storDischarge]; header = [:Node, :Storage, :Time, :Discharge])
    storDischarge = filter(r -> r.Discharge > 0.0, storDischarge)

    storCharge = Containers.rowtable(value, emp[:storCharge]; header = [:Node, :Storage, :Time, :Charge])
    storCharge = filter(r -> r.Charge > 0.0, storCharge)

    storOperational = Containers.rowtable(value, emp[:storOperational]; header = [:Node, :Storage, :Time, :Charge])
    storOperational = filter(r -> r.Charge > 0.0, storOperational)

    trOperational = Containers.rowtable(value, emp[:transmissionOperational]; header = [:Node1, :Node2, :Time, :Flow])
    trOperational = filter(r -> r.Flow > 0.0, trOperational)

    shed = Containers.rowtable(value, emp[:loadShed]; header = [:Node, :Time, :Shed])
    shed = filter(r -> r.Shed > 0.0, shed)

    sc = first(opscenarios(periods))

    for t in sc
        println("Time period: $t")
        println("===================================")
        println("Load:")
        for n in sets.Node
            println("  Node: $n, Load: $(OpenEMPIRE.load(params, n, t))")
        end
        println("Generation:")
        for r in filter(r -> r.Time == t, prod)
            println("  Node: $(r.Node), Generator: $(r.Generator), Production: $(r.Production)")
        end
        println("Storage Discharge:")
        for r in filter(r -> r.Time == t, storDischarge)
            println("  Node: $(r.Node), Storage: $(r.Storage), Discharge: $(r.Discharge)")
        end
        println("Storage Charge:")
        for r in filter(r -> r.Time == t, storCharge)
            println("  Node: $(r.Node), Storage: $(r.Storage), Charge: $(r.Charge)")
        end
        println("Storage Operational:")
        for r in filter(r -> r.Time == t, storOperational)
            println("  Node: $(r.Node), Storage: $(r.Storage), Charge: $(r.Charge)")
        end
        println("Transmission Flow:")
        for r in filter(r -> r.Time == t, trOperational)
            println("  Node1: $(r.Node1), Node2: $(r.Node2), Flow: $(r.Flow)")
        end
        println("Load Shedding:")
        for r in filter(r -> r.Time == t, shed)
            println("  Node: $(r.Node), Shed: $(r.Shed)")
        end
    end
end
