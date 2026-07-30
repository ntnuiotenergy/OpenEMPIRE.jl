function test_solve()

	source_folder = joinpath(pkgdir(OpenEMPIRE), "data", "test_excel")

	# Scenario generation writes sampling_key.csv and the generated stochastic
	# CSVs back into the dataset folder, so run against a copy. Pointing at the
	# tracked folder leaves the repository dirty after every test run.
	mktempdir() do root
		data_folder = joinpath(root, "test_excel")
		cp(source_folder, data_folder)
		config_file = joinpath(data_folder, "testrun.yaml")

		emp, periods, sets, params = OpenEMPIRE.create_model(config_file, data_folder; optimizer = HiGHS.Optimizer)

		optimize!(emp)

		@test termination_status(emp) == MOI.OPTIMAL
		@test primal_status(emp) == MOI.FEASIBLE_POINT
		@test isfinite(objective_value(emp))
	end
end
