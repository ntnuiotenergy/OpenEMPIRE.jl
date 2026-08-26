function _country_test_sets_kwargs()
    return (
        Generator = ["gas"],
        ThermalGenerators = ["gas"],
        Storage = String[],
        Technology = ["thermal"],
        Node = ["DK01", "DK02", "NO01", "NO02", "France"],
        DirectionalLink = [("DK01", "DK02"), ("DK02", "DK01")],
        TransmissionType = ["HVDC"],
        TransmissionTypeOfDirectionalLink = [("DK01", "DK02", "HVDC"), ("DK02", "DK01", "HVDC")],
        GeneratorsOfTechnology = [("thermal", "gas")],
        GeneratorsOfNode = [
            ("DK01", "gas"),
            ("DK02", "gas"),
            ("NO01", "gas"),
            ("NO02", "gas"),
            ("France", "gas"),
        ],
        StoragesOfNode = Tuple{String, String}[],
    )
end

function test_empire_sets_countries_default_empty()
    sets = OpenEMPIRE.EmpireSets(; _country_test_sets_kwargs()...)

    @test OpenEMPIRE.countries(sets) == String[]
    @test OpenEMPIRE.nodes_of_country(sets) == Tuple{String, String}[]
    @test OpenEMPIRE.nodes_of_country(sets, "Denmark") == String[]
    @test OpenEMPIRE.country_of_node(sets, "DK01") === nothing
    @test OpenEMPIRE.validate!(sets) === sets
end

function test_empire_sets_explicit_empty_country_mapping()
    sets = OpenEMPIRE.EmpireSets(;
        _country_test_sets_kwargs()...,
        Countries = String[],
        NodesOfCountry = Tuple{String, String}[],
    )

    @test OpenEMPIRE.countries(sets) == String[]
    @test OpenEMPIRE.nodes_of_country(sets) == Tuple{String, String}[]
    @test OpenEMPIRE.country_of_node(sets, "DK01") === nothing
end

function test_empire_sets_countries_positional_constructor_unchanged()
    kwargs = _country_test_sets_kwargs()
    sets = OpenEMPIRE.EmpireSets(
        kwargs.Generator,
        Set(kwargs.ThermalGenerators),
        Set{String}(),
        Set{String}(),
        kwargs.Storage,
        Set{String}(),
        kwargs.Technology,
        kwargs.Node,
        Set{String}(),
        Set{String}(),
        kwargs.DirectionalLink,
        kwargs.TransmissionType,
        kwargs.TransmissionTypeOfDirectionalLink,
        kwargs.GeneratorsOfTechnology,
        kwargs.GeneratorsOfNode,
        kwargs.StoragesOfNode;
        validate = true,
    )

    @test OpenEMPIRE.countries(sets) == String[]
    @test OpenEMPIRE.nodes_of_country(sets) == Tuple{String, String}[]
end

function test_empire_sets_nodes_of_country_accessors()
    sets = OpenEMPIRE.EmpireSets(;
        _country_test_sets_kwargs()...,
        Countries = ["Denmark", "Norway"],
        NodesOfCountry = [
            ("Denmark", "DK01"),
            ("Denmark", "DK02"),
            ("Norway", "NO01"),
            ("Norway", "NO02"),
        ],
    )

    @test Set(OpenEMPIRE.countries(sets)) == Set(["Denmark", "Norway"])
    @test Set(OpenEMPIRE.nodes_of_country(sets, "Denmark")) == Set(["DK01", "DK02"])
    @test Set(OpenEMPIRE.nodes_of_country(sets, "Norway")) == Set(["NO01", "NO02"])
    @test OpenEMPIRE.nodes_of_country(sets, "France") == String[]
    @test OpenEMPIRE.country_of_node(sets, "DK01") == "Denmark"
    @test OpenEMPIRE.country_of_node(sets, "NO02") == "Norway"
    @test OpenEMPIRE.country_of_node(sets, "France") === nothing
end

function test_empire_sets_country_validation()
    kwargs = _country_test_sets_kwargs()

    @test_throws ArgumentError OpenEMPIRE.EmpireSets(;
        kwargs...,
        Countries = ["Denmark"],
        NodesOfCountry = [("Denmark", "DK99")],
    )
    @test_throws ArgumentError OpenEMPIRE.EmpireSets(;
        kwargs...,
        NodesOfCountry = [("Denmark", "DK01")],
    )
    @test_throws ArgumentError OpenEMPIRE.EmpireSets(;
        kwargs...,
        Countries = ["Denmark", "Norway"],
        NodesOfCountry = [("Denmark", "DK01"), ("Norway", "DK01")],
    )
    @test_throws ArgumentError OpenEMPIRE.EmpireSets(;
        kwargs...,
        Countries = ["Denmark", "Norway"],
        NodesOfCountry = [("Norway", "NO01")],
    )
end
