


function test_interface()

    data_folder = joinpath(pkgdir(OpenEMPIRE), "data")
    config_file = joinpath(data_folder, "testrun.yaml")

    config_file = "../OpenEMPIRE/config/run.yaml"
    data_folder = "../OpenEMPIRE/Data handler/europe_v51"

    emp, periods, sets, params = OpenEMPIRE.create_model(config_file, data_folder; optimizer = HiGHS.Optimizer);
    optimize!(emp)

    write_to_file(emp, "empire.lp")

    sps = strat_periods(periods)
    @constraint(emp, emp[:storENInvCap]["Germany", "Li-Ion_BESS", last(sps)] == 4000)


    gen = Containers.rowtable(value, emp[:genOperational]; header = [:Node, :Generator, :Time, :Production])
    gen = filter(r -> r.Production > 0.0, gen)

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

    sc = last(opscenarios(periods))

    for t in sc
        println("Time period: $t")
        println("===================================")
        println("Load:")
        for n in sets.Node
            println("  Node: $n, Load: $(OpenEMPIRE.load(params, n, t))")
        end
        println("Generation:")
        for r in filter(r -> r.Time == t, gen)
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


    genInstalledCap = Containers.rowtable(value, emp[:genInstalledCap]; header = [:Node, :Generator, :Period, :Capacity])
    storENInstalledCap = Containers.rowtable(value, emp[:storENInstalledCap]; header = [:Node, :Storage, :Period, :EnergyCapacity])
    storPWInstalledCap = Containers.rowtable(value, emp[:storPWInstalledCap]; header = [:Node, :Storage, :Period, :PowerCapacity])

    genInvCap = Containers.rowtable(value, emp[:genInvCap]; header = [:Node, :Generator, :Period, :Investment])
    storENInvCap = Containers.rowtable(value, emp[:storENInvCap]; header = [:Node, :Storage, :Period, :EnergyCapacity])
    storPWInvCap = Containers.rowtable(value, emp[:storPWInvCap]; header = [:Node, :Storage, :Period, :PowerCapacity])
    transInvCap = Containers.rowtable(value, emp[:transmissionInvCap]; header = [:Node1, :Node2, :Period, :Capacity])


    using PrettyTables

    pretty_table(filter(r -> r.Investment > 0, genInvCap))

end

no_space(gen) = replace(gen, r"\s" => "")

function test_preproces()

    using CSV
    empire_res = "../OpenEMPIRE/Results/basic_run/dataset_test/Output"

    emp, periods, sets, params = OpenEMPIRE.create_model(config_file, data_folder; optimizer = HiGHS.Optimizer);


    gen_data = CSV.File(joinpath(empire_res, "investment_costs.csv"); delim = ',')
    sps = collect(strat_periods(periods))
    for r in gen_data
        g = String(r.Generator)
        sp = Int(r.Period)
        cost = Float64(r.InvestmentCost_EurperMW)
        gg = [gen  for gen in sets.Generator if no_space(gen) == g][1]
        if abs(cost - OpenEMPIRE.gen_invest_cost(params, gg, sps[sp])) > 1e-5
            println("Mismatch in investment cost for generator $g in strategic period $sp: $cost vs $(OpenEMPIRE.gen_invest_cost(params, g, sps[sp]))")
        end
    end

    marg_data = CSV.File(joinpath(empire_res, "marginal_costs.csv"); delim = ',')
    for r in marg_data
        g = String(r.Generator)
        sp = Int(r.Period)
        cost = Float64(r.MarginalCost_EurperMWh)
        gg = [gen  for gen in sets.Generator if no_space(gen) == g][1]
        if abs(cost - OpenEMPIRE.gen_marginal_cost(params, gg, sps[sp])) > 1e-5
            println("Mismatch in marginal cost for generator $g in strategic period $sp: $cost vs $(OpenEMPIRE.gen_marginal_cost(params, g, sps[sp]))")
        end
    end

end

function test_empire_sol()

    data_folder = joinpath(pkgdir(OpenEMPIRE), "data")
    config_file = joinpath(data_folder, "testrun.yaml")

    emp, periods, sets, params = OpenEMPIRE.create_model(config_file, data_folder; optimizer = HiGHS.Optimizer);

    sps = strat_periods(periods)

    empire_res = "../OpenEMPIRE/Results/basic_run/dataset_test/Output"


    gen_data = CSV.File(joinpath(empire_res, "genInvCap.tab"); delim = '\t')

    for r in gen_data
        n = String(r.Node)
        g = String(r.Generator)
        sp = Int(r.Period)
        cap = Float64(r.genInvCap)
        gg = [gen  for gen in sets.Generator if no_space(gen) == g][1]
        println("Setting genInvCap for $n, $gg, $sp to $cap")
        @constraint(emp, emp[:genInvCap][n, gg, sps[sp]] == cap)
    end

    store_data = CSV.File(joinpath(empire_res, "storENInvCap.tab"); delim = '\t')

    for r in store_data
        n = String(r.Node)
        s = String(r.Storage)
        sp = Int(r.Period)
        cap = Float64(r.storENInvCap)
        ss = [sto  for sto in sets.Storage if no_space(sto) == s][1]
        println("Setting storENInvCap for $n, $ss, $sp to $cap")
        @constraint(emp, emp[:storENInvCap][n, ss, sps[sp]] == cap)
    end

    storp_data = CSV.File(joinpath(empire_res, "storPWInvCap.tab"); delim = '\t')
    for r in storp_data
        n = String(r.Node)
        s = String(r.Storage)
        sp = Int(r.Period)
        cap = Float64(r.storPWInvCap)
        ss = [sto  for sto in sets.Storage if no_space(sto) == s][1]
        println("Setting storPWInvCap for $n, $ss, $sp to $cap")
        @constraint(emp, emp[:storPWInvCap][n, ss, sps[sp]] == cap)
    end
|
    transm_data = CSV.File(joinpath(empire_res, "transmisionInvCap.tab"); delim = '\t')

    for r in transm_data
        n1 = String(r.FromNode)
        n2 = String(r.ToNode)
        sp = Int(r.Period)
        cap = Float64(r.transmisionInvCap)
        println("Setting transInvCap for $n1, $n2, $sp to $cap")
        @constraint(emp, emp[:transmissionInvCap][n1, n2, sps[sp]] == cap)
    end

    write_to_file(emp, "empire_test.lp")


    optimize!(emp)


    inv_cost = OpenEMPIRE.sol_invest_cost(emp, sets, params, periods, Discounter(params.discountRate, 1, periods))
    gen_cost, load_shed_cost = OpenEMPIRE.sol_operational_cost(emp, sets, params, periods, Discounter(params.discountRate, 1, periods))


    df = DataFrame(CSV.File(joinpath(empire_res, "results_output_Operational.csv"); delim = ','))

    sum(df.LoadShed_MW)

    ls = DataFrame(Containers.rowtable(value, emp[:loadShed]; header = [:Node, :Time, :Shed]))
    gen = DataFrame(Containers.rowtable(value, emp[:genOperational]; header = [:Node, :Generator, :Time, :Production]))
end
