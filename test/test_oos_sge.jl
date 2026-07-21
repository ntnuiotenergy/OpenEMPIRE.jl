function test_parse_oos_sge_output()
    @test OpenEMPIRE.parse_oos_sge_qsub_output(
        "Your job 12345 (\"empire_oos_1\") has been submitted\n",
    ) == "12345"
    @test OpenEMPIRE.parse_oos_sge_qsub_output(
        "Your job-array 54321.1-3:1 (\"trees\") has been submitted\n",
    ) == "54321"
    @test_throws ArgumentError OpenEMPIRE.parse_oos_sge_qsub_output("submission failed")

    qstat = """job-ID  prior   name       user         state submit/start at     queue                          slots
--------------------------------------------------------------------------------------------------------------
12345   0.55500 empire     intern       qw    07/20/2026 12:00:00                                    1
12346   0.55500 empire2    intern       r     07/20/2026 12:01:00 all.q@compute-4-51.local     1
12347   0.55500 empire3    intern       Eqw   07/20/2026 12:02:00                                    1
"""
    waiting = OpenEMPIRE.parse_oos_sge_qstat_output(qstat, "12345")
    @test waiting["status"] == "submitted"
    @test waiting["raw_state"] == "qw"
    running = OpenEMPIRE.parse_oos_sge_qstat_output(qstat, "12346")
    @test running["status"] == "running"
    @test running["queue"] == "all.q@compute-4-51.local"
    @test OpenEMPIRE.parse_oos_sge_qstat_output(qstat, "12347")["status"] == "failed"
    @test isnothing(OpenEMPIRE.parse_oos_sge_qstat_output(qstat, "99999"))

    successful_qacct = """==============================================================
qname        all.q
hostname     compute-4-51.local
jobnumber    12345
failed       0
exit_status  0
ru_wallclock 3600.000
maxvmem      140.000G
"""
    successful = OpenEMPIRE.parse_oos_sge_qacct_output(successful_qacct, "12345")
    @test successful["status"] == "finished"
    @test successful["fields"]["maxvmem"] == "140.000G"

    failed_qacct = replace(successful_qacct, "failed       0" => "failed       1")
    @test OpenEMPIRE.parse_oos_sge_qacct_output(failed_qacct, "12345")["status"] ==
          "failed"
    @test_throws ArgumentError OpenEMPIRE.parse_oos_sge_qacct_output(
        successful_qacct,
        "99999",
    )
end

function test_oos_solstorm_project_bootstrap()
    mktempdir() do root
        fake_julia = joinpath(root, "fake-julia")
        ready_file = joinpath(root, "ready")
        log_file = joinpath(root, "calls.log")
        write(fake_julia, """#!/bin/bash
echo \"\$*\" >> \"\$FAKE_JULIA_LOG\"
if [[ \"\$*\" == *\"using Pkg; Pkg.instantiate(); Pkg.precompile()\"* ]]; then
    [[ \"\${FAKE_INSTANTIATE_FAIL:-0}\" == \"1\" ]] && exit 9
    touch \"\$FAKE_JULIA_READY\"
    exit 0
fi
[[ -f \"\$FAKE_JULIA_READY\" ]]
""")
        chmod(fake_julia, 0o755)
        shell = OpenEMPIRE._oos_solstorm_project_bootstrap(
            root,
            fake_julia;
            solver = "Gurobi",
        )
        @test occursin("OpenEMPIRE Solstorm project dependency bootstrap", shell)
        @test occursin("import Gurobi", shell)

        environment = Dict(
            "FAKE_JULIA_LOG" => log_file,
            "FAKE_JULIA_READY" => ready_file,
        )
        process = run(ignorestatus(setenv(`bash -c $shell`, environment)))
        @test success(process)
        calls = readlines(log_file)
        @test length(calls) == 3
        @test occursin("import OpenEMPIRE", calls[1])
        @test occursin("Pkg.instantiate()", calls[2])
        @test occursin("import OpenEMPIRE", calls[3])

        write(log_file, "")
        process = run(ignorestatus(setenv(`bash -c $shell`, environment)))
        @test success(process)
        calls = readlines(log_file)
        @test length(calls) == 2
        @test all(!occursin("Pkg.instantiate()", call) for call in calls)

        rm(ready_file)
        write(log_file, "")
        failing_environment = merge(environment, Dict("FAKE_INSTANTIATE_FAIL" => "1"))
        process = run(ignorestatus(setenv(`bash -c $shell`, failing_environment)))
        @test !success(process)
        calls = readlines(log_file)
        @test length(calls) == 2
        @test occursin("Pkg.instantiate()", calls[2])
    end
end

function test_prepare_and_record_oos_sge_job()
    mktempdir() do root
        source_data = joinpath(root, "source")
        cp(joinpath(pkgdir(OpenEMPIRE), "data", "test"), source_data)
        config_file = joinpath(pkgdir(OpenEMPIRE), "config", "testrun.yaml")
        experiment_dir = OpenEMPIRE.prepare_oos_experiment(
            config_file,
            source_data,
            joinpath(root, "experiment");
            num_trees = 1,
            seed_start = 150,
            input_format = :csv,
        )
        fixed_investment_dir = joinpath(root, "investment_run")
        _write_investment_csvs(joinpath(fixed_investment_dir, "Output"))
        results_root = joinpath(root, "results")
        queue_file = OpenEMPIRE.prepare_oos_execution_queue(
            experiment_dir,
            fixed_investment_dir;
            dataset = source_data,
            config_file,
            results_root,
            input_format = :csv,
            solver = "HiGHS",
        )

        sge_dir = joinpath(root, "sge")
        plan = OpenEMPIRE.prepare_oos_sge_job(queue_file; output_dir = sge_dir)
        @test plan["kind"] == "sge"
        @test plan["cluster"] == "Solstorm"
        @test plan["status"] == "prepared"
        @test plan["submit_command"] == ["qsub", plan["script"]]
        @test isfile(plan["script"])
        @test !ispath(results_root)

        script = read(plan["script"], String)
        @test occursin("#\$ -cwd", script)
        @test occursin("#\$ -l hostname=", script)
        @test occursin("module load gurobi/13.0", script)
        @test occursin("OpenEMPIRE Solstorm Julia bootstrap", script)
        @test occursin("source /etc/profile", script)
        @test occursin("module load Julia/1.9.3", script)
        @test occursin("command -v julia", script)
        @test occursin("OpenEMPIRE Solstorm project dependency bootstrap", script)
        @test occursin("Pkg.instantiate()", script)
        @test occursin("Pkg.precompile()", script)
        @test occursin("_validate_oos_execution_queue_inputs", script)
        @test occursin("--out-of-sample=true", script)
        @test occursin("--scenario-data-root=$(joinpath(experiment_dir, "oos_tree1"))", script)
        @test !occursin(r"(?m)^qsub ", script)

        repeated = OpenEMPIRE.prepare_oos_sge_job(queue_file; output_dir = sge_dir)
        @test repeated == plan
        queued = YAML.load_file(queue_file)
        @test queued["jobs"][1]["status"] == "pending"
        @test queued["jobs"][1]["scheduler"]["script_sha256"] ==
              OpenEMPIRE._oos_sha256_file(plan["script"])

        submitted = OpenEMPIRE.record_oos_sge_submission!(
            queue_file,
            1,
            "Your job 77777 (\"empire_oos_1\") has been submitted\n",
        )
        @test submitted["status"] == "submitted"
        @test submitted["scheduler_job_id"] == "77777"
        @test endswith(submitted["stdout_path"], "oos_tree1_77777.out")

        qstat = """job-ID prior name user state submit/start at queue slots
77777 0.5 empire intern r 07/20/2026 12:00:00 all.q@compute-4-51.local 1
"""
        running = OpenEMPIRE.record_oos_sge_qstat!(queue_file, 1, qstat)
        @test running["status"] == "running"
        @test running["scheduler"]["raw_state"] == "r"

        qacct = """==============================================================
hostname     compute-4-51.local
jobnumber    77777
failed       0
exit_status  0
ru_wallclock 42.000
maxvmem      1.500G
"""
        finished = OpenEMPIRE.record_oos_sge_qacct!(queue_file, 1, qacct)
        @test finished["status"] == "finished"
        @test finished["scheduler"]["accounting"]["maxvmem"] == "1.500G"
        @test YAML.load_file(queue_file)["status"] == "reconciling"

        queue = YAML.load_file(queue_file)
        result_dir = _write_test_oos_run_manifest(
            queue,
            queue["jobs"][1];
            status = "complete",
            termination = "OPTIMAL",
        )
        reconciled = OpenEMPIRE.reconcile_oos_execution_queue!(queue_file)
        @test reconciled["status"] == "complete"
        @test reconciled["jobs"][1]["status"] == "complete"
        @test reconciled["jobs"][1]["result_dir"] == result_dir
        @test reconciled["jobs"][1]["history"][end]["from"] == "finished"
        @test reconciled["jobs"][1]["history"][end]["source"] == "reconcile"
    end
end
