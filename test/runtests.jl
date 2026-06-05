
using HiGHS
using JuMP
using OpenEMPIRE
using Test
using TimeStruct
# using Xpress

include("test_excel.jl")
#include("test_interface.jl")
include("test_timestruct.jl")

@testset "Excel" begin
    test_read_excel_sets()
    test_read_excel_params()
end

@testset "Validate" begin
    test_validate_params()
end

# @testset "Interface" begin
#     test_interface()
# end

@testset "TimeStruct" begin
    test_timestruct()
    test_variables()
    test_variable_large()
    test_constraints()
end
