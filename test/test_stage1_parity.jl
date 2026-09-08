# Stage-1 parity: input seasScale path + offshore-node alignment.

# --- use_input_season_scale / create_timestruct(regular_season_scale, peak_season_scale) --

function test_input_season_scale_multiplier()
    S  = 12.96428571428571      # General.xlsx!seasonScale regular value (bit-identical both sides)
    Sp = 1.0
    tl = OpenEMPIRE.create_timestruct(2, 5, 4, 24, 2, 24, 2;
        regular_season_scale = S, peak_season_scale = Sp)
    sp1 = first(strat_periods(tl))
    rps = collect(repr_periods(sp1))
    t_reg = first(first(TimeStruct.opscenarios(rps[1])))
    t_pk  = first(first(TimeStruct.opscenarios(rps[5])))
    ms_reg = multiple_strat(sp1, t_reg)
    ms_pk  = multiple_strat(sp1, t_pk)
    # peak lands exactly; regular within 1 ULP of the input value (documented tolerance)
    @test ms_pk == Sp
    @test abs(ms_reg - S) <= eps(S)
    @test isapprox(ms_reg, S; rtol = 2e-16)
end

function test_default_time_structure_unchanged()
    tl = OpenEMPIRE.create_timestruct(2, 5, 4, 24, 2, 24, 2)   # no scale kwargs
    sp1 = first(strat_periods(tl))
    rps = collect(repr_periods(sp1))
    t_reg = first(first(TimeStruct.opscenarios(rps[1])))
    t_pk  = first(first(TimeStruct.opscenarios(rps[5])))
    @test multiple_strat(sp1, t_reg) == 90.75      # (8760 - 48) / (4 * 24)
    @test multiple_strat(sp1, t_pk) == 1.0
end

function test_season_scale_requires_both_or_neither()
    @test_throws ArgumentError OpenEMPIRE.create_timestruct(
        2, 5, 4, 24, 2, 24, 2; regular_season_scale = 12.0)
    @test_throws ArgumentError OpenEMPIRE.create_timestruct(
        2, 5, 4, 24, 2, 24, 2; peak_season_scale = 1.0)
end

function test_input_season_scale_reads_northsea_csv()
    ds = joinpath(pkgdir(OpenEMPIRE), "data", "NorthSea_NECPEssentials")
    isdir(ds) || return
    r, p = OpenEMPIRE._input_season_scale(ds, ("winter", "spring", "summer", "fall"), 2)
    @test r == 12.96428571428571
    @test p == 1.0
end

# --- offshore-node alignment: OffshoreWindFarmNode.csv == Sets.xlsx!OffshoreNodes -----

const _NS_OFFSHORE_AUTHORITATIVE = Set([
    "Borssele", "DoggerBank", "EastAnglia", "FirthofForth", "HelgolanderBucht",
    "HollandseeKust", "Hornsea", "MorayFirth", "Nordsoen", "Norfolk",
    "OuterDowsing", "SorligeNordsjoI", "SorligeNordsjoII", "UtsiraNord",
])

function test_northsea_offshore_windfarm_set_matches_excel()
    ds = joinpath(pkgdir(OpenEMPIRE), "data", "NorthSea_NECPEssentials")
    isdir(ds) || return
    sets = OpenEMPIRE.read_sets_csv(ds)
    wf = Set(String.(OpenEMPIRE.offshore_wind_farm_nodes(sets)))
    @test length(wf) == 14
    @test wf == _NS_OFFSHORE_AUTHORITATIVE
    @test isempty(OpenEMPIRE.offshore_energy_hubs(sets))
    # every member is a real node with generators (validate! would have rejected otherwise)
    @test wf ⊆ Set(OpenEMPIRE.nodes(sets))
end
