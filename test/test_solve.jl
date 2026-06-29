function test_solve()

	data_folder = joinpath(pkgdir(OpenEMPIRE), "data", "test_excel")
	config_file = joinpath(data_folder, "testrun.yaml")

	emp, periods, sets, params = OpenEMPIRE.create_model(config_file, data_folder; optimizer = HiGHS.Optimizer)

	optimize!(emp)

	@test termination_status(emp) == MOI.OPTIMAL
	@test primal_status(emp) == MOI.FEASIBLE_POINT
	@test isfinite(objective_value(emp))
end
