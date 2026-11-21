const _BOUNDED_WORKER_FORWARD_CACHE = Dict{Int, Tuple{Any, Any}}()

function benders_live_log_dir()
    configured = get(ENV, "OPENEMPIRE_LIVE_LOG_DIR", "")
    if !isempty(configured)
        dir = configured
    elseif isdir("/storage")
        dir = joinpath("/storage", "OpenEMPIRE", "benders_live")
    else
        dir = joinpath(pwd(), "benders_live")
    end
    mkpath(joinpath(dir, "gurobi", "master"))
    mkpath(joinpath(dir, "gurobi", "sp"))
    return dir
end

function setup_benders_live_logging(; implementation = "benders")
    dir = benders_live_log_dir()
    ENV["OPENEMPIRE_BENDERS_IMPLEMENTATION"] = implementation
    iterations_file = joinpath(dir, "iterations.csv")
    if !isfile(iterations_file)
        open(iterations_file, "w") do io
            println(
                io,
                "iteration,lower_bound,upper_bound,best_upper_bound,gap," *
                "root_seconds,worker_batch_seconds,worker_solver_seconds," *
                "worker_overhead_seconds,cut_seconds,total_seconds",
            )
        end
    end
    write_benders_live_status("RUNNING"; implementation = implementation)
    return dir
end

function write_benders_live_status(status; implementation = "benders", iteration = nothing)
    dir = benders_live_log_dir()
    implementation = get(
        ENV,
        "OPENEMPIRE_BENDERS_IMPLEMENTATION",
        implementation,
    )
    open(joinpath(dir, "status.txt"), "w") do io
        println(io, status)
        println(io, "implementation=$implementation")
        iteration === nothing || println(io, "iteration=$iteration")
        println(io, "updated=$(Dates.format(now(), dateformat"yyyy-mm-ddTHH:MM:SS"))")
    end
    return nothing
end

function append_benders_live_iteration!(;
    iteration,
    lower_bound,
    upper_bound,
    best_upper_bound,
    gap,
    root_seconds,
    worker_batch_seconds,
    worker_solver_seconds,
    worker_overhead_seconds,
    cut_seconds,
    total_seconds,
)
    dir = benders_live_log_dir()
    open(joinpath(dir, "iterations.csv"), "a") do io
        println(
            io,
            join((
                iteration,
                lower_bound,
                upper_bound,
                best_upper_bound,
                gap,
                root_seconds,
                worker_batch_seconds,
                worker_solver_seconds,
                worker_overhead_seconds,
                cut_seconds,
                total_seconds,
            ), ","),
        )
    end
    write_benders_live_status("RUNNING"; iteration = iteration)
    return nothing
end

function benders_master_gurobi_log(iteration)
    dir = joinpath(benders_live_log_dir(), "gurobi", "master")
    mkpath(dir)
    return joinpath(dir, "iter_$(lpad(iteration, 6, '0')).log")
end

function benders_subproblem_gurobi_log(subproblem_index, iteration)
    sp_dir = joinpath(
        benders_live_log_dir(),
        "gurobi",
        "sp",
        "SP_$(lpad(subproblem_index, 6, '0'))",
    )
    mkpath(sp_dir)
    return joinpath(sp_dir, "iter_$(lpad(iteration, 6, '0')).log")
end

function _bounded_worker_forward_state(job)
    state = get(_BOUNDED_WORKER_FORWARD_CACHE, job.index, nothing)
    if state === nothing
        job.darray === nothing &&
            error("Missing graph handle when initializing worker subproblem cache")
        job.var_copies === nothing &&
            error("Missing variable proxies when initializing worker subproblem cache")

        lgraph = Plasmo.local_graph(job.darray)
        lvar_copies = Plasmo._convert_proxy_to_local(
            lgraph,
            job.var_copies,
        )
        state = (lgraph, lvar_copies)
        _BOUNDED_WORKER_FORWARD_CACHE[job.index] = state
    end
    return state
end

function _optimize_remote_graph_forward_batch(
    optimizer,
    objects;
    initialize_worker_cache = false,
)
    isempty(objects) && return Any[]

    worker = first(objects).object.worker
    jobs = NamedTuple[]

    for job in objects
        object = job.object
        primal_iters = optimizer.primal_iters[object]
        last_primals = primal_iters[:, size(primal_iters, 2)]

        push!(
            jobs,
            initialize_worker_cache ?
            (
                index = job.index,
                iteration = optimizer.current_iter + 1,
                darray = job.darray,
                var_copies = job.var_copies,
                last_primals = last_primals,
            ) :
            (
                index = job.index,
                iteration = optimizer.current_iter + 1,
                last_primals = last_primals,
            ),
        )
    end

    add_slacks = PlasmoBenders.get_add_slacks(optimizer)
    feasibility_cuts = PlasmoBenders.get_feasibility_cuts(optimizer)
    is_MIP = PlasmoBenders.get_is_MIP(optimizer)

    remote_fetch = getfield(Main.Distributed, :remotecall_fetch)
    return remote_fetch(worker, initialize_worker_cache, jobs) do clear_cache, remote_jobs
        clear_cache && empty!(_BOUNDED_WORKER_FORWARD_CACHE)
        results = Any[]

        for job in remote_jobs
            lgraph, lvar_copies = _bounded_worker_forward_state(job)

            gurobi_log = benders_subproblem_gurobi_log(job.index, job.iteration)
            JuMP.set_optimizer_attribute(lgraph, "LogToConsole", 0)
            JuMP.set_optimizer_attribute(lgraph, "LogFile", gurobi_log)
            JuMP.fix.(lvar_copies, job.last_primals, force = true)
            t_solve = @elapsed JuMP.optimize!(lgraph)
            open(joinpath(dirname(gurobi_log), "latest.txt"), "w") do io
                println(io, gurobi_log)
                flush(io)
            end

            feasible = PlasmoBenders._check_termination_status(
                lgraph,
                job.index;
                add_slacks_bool = add_slacks,
                feasibility_cuts_bool = feasibility_cuts,
            )

            if feasibility_cuts && !feasible
                objective = JuMP.dual_objective_value(lgraph)
                duals = is_MIP ? nothing : Float64[
                    JuMP.dual(lgraph, JuMP.FixRef(var))
                    for var in lvar_copies
                ]
            elseif feasible
                objective = JuMP.value(
                    lgraph,
                    JuMP.objective_function(lgraph),
                )
                duals = is_MIP ? nothing : Float64[
                    JuMP.dual(lgraph, JuMP.FixRef(var))
                    for var in lvar_copies
                ]
            else
                error(
                    "Remote Benders subproblem $(job.index) terminated " *
                    "with status $(JuMP.termination_status(lgraph))",
                )
            end

            push!(results, (job.index, feasible, objective, duals, t_solve))
        end

        results
    end
end

function run_benders_by_worker!(optimizer; output = true, run_gc = false)
    optimizer.is_MIP &&
        error("run_benders_by_worker! currently supports linear Benders models only")

    bounded_timings = NamedTuple[]
    optimizer.ext["bounded_iteration_timings"] = bounded_timings

    worker_groups = Dict{Int, Vector{NamedTuple}}()
    for index in 2:length(optimizer.solve_order)
        object = optimizer.solve_order[index]
        comp_vars = optimizer.comp_vars[object]
        var_copy_map = optimizer.var_copy_map[object]
        var_copies = [var_copy_map[var] for var in comp_vars]
        proxy_copies = Plasmo._convert_remote_to_proxy(object, var_copies)

        push!(
            get!(worker_groups, object.worker, NamedTuple[]),
            (
                index = index,
                object = object,
                darray = object.graph,
                var_copies = proxy_copies,
            ),
        )
    end

    while optimizer.current_iter < optimizer.max_iters
        root_object = optimizer.solve_order[1]
        root_start = time()
        root_iteration = optimizer.current_iter + 1
        JuMP.set_optimizer_attribute(
            root_object,
            "LogToConsole",
            0,
        )
        JuMP.set_optimizer_attribute(
            root_object,
            "LogFile",
            benders_master_gurobi_log(root_iteration),
        )
        JuMP.optimize!(root_object)
        root_solve_time = time() - root_start
        optimizer.time_root_problem_solve += root_solve_time

        PlasmoBenders._check_termination_status(
            root_object,
            1;
            add_slacks_bool = PlasmoBenders.get_add_slacks(optimizer),
            feasibility_cuts_bool = PlasmoBenders.get_feasibility_cuts(optimizer),
        )

        root_objective = JuMP.objective_value(root_object)
        lower_bound = root_objective
        PlasmoBenders._save_subproblem_objective!(optimizer, root_object)

        for object in optimizer.solve_order_dict[root_object]
            comp_vars = optimizer.comp_vars[object]
            primals = PlasmoBenders._get_variable_values(root_object, comp_vars)
            optimizer.primal_iters[object] = reshape(copy(primals), :, 1)
        end
        optimizer.last_solutions[root_object] =
            PlasmoBenders._get_object_last_solutions(root_object)

        worker_timings = Dict{Int, NamedTuple}()
        worker_batch_start = time()

        @sync for (worker_id, objects) in worker_groups
            @async begin
                worker_start = time()
                results = _optimize_remote_graph_forward_batch(
                    optimizer,
                    objects,
                    initialize_worker_cache = optimizer.current_iter == 0,
                )
                worker_wall_seconds = time() - worker_start
                worker_solver_seconds = sum(result[5] for result in results)
                worker_timings[worker_id] = (
                    wall_seconds = worker_wall_seconds,
                    solver_seconds = worker_solver_seconds,
                    overhead_seconds = max(
                        worker_wall_seconds - worker_solver_seconds,
                        0.0,
                    ),
                )

                for (index, feasible, objective, duals, solve_time) in results
                    object = optimizer.solve_order[index]

                    optimizer.time_subproblem_solves += solve_time
                    optimizer.feasibility_map[object] = feasible
                    optimizer.subgraph_objectives[object] =
                        feasible ? objective : Inf

                    optimizer.dual_iters[object] = reshape(copy(duals), :, 1)
                    push!(optimizer.phis[object], objective)
                end
            end
        end

        worker_batch_wall_seconds = time() - worker_batch_start
        worker_solver_seconds = sum(
            timing.solver_seconds for timing in values(worker_timings)
        )
        worker_overhead_seconds = max(
            worker_batch_wall_seconds - worker_solver_seconds,
            0.0,
        )

        upper_bound = sum(
            optimizer.subgraph_objectives[object]
            for object in optimizer.solve_order
        )
        if upper_bound < optimizer.best_upper_bound ||
           isempty(optimizer.upper_bounds)
            optimizer.best_upper_bound = upper_bound
        end

        cut_start = time()
        PlasmoBenders._add_Benders_cuts!(optimizer)
        cut_seconds = time() - cut_start

        push!(optimizer.lower_bounds, lower_bound)
        push!(optimizer.upper_bounds, upper_bound)
        iteration_seconds = time() - root_start
        push!(optimizer.time_iterations, iteration_seconds)
        optimizer.current_iter += 1

        push!(
            bounded_timings,
            (
                iteration = optimizer.current_iter,
                total_seconds = iteration_seconds,
                root_seconds = root_solve_time,
                worker_batch_seconds = worker_batch_wall_seconds,
                worker_solver_seconds = worker_solver_seconds,
                worker_overhead_seconds = worker_overhead_seconds,
                cut_seconds = cut_seconds,
                workers = worker_timings,
            ),
        )

        gap = if optimizer.best_upper_bound != 0
            abs((optimizer.best_upper_bound - lower_bound) / optimizer.best_upper_bound)
        else
            abs(optimizer.best_upper_bound - lower_bound)
        end

        append_benders_live_iteration!(
            iteration = optimizer.current_iter,
            lower_bound = lower_bound,
            upper_bound = upper_bound,
            best_upper_bound = optimizer.best_upper_bound,
            gap = gap,
            root_seconds = root_solve_time,
            worker_batch_seconds = worker_batch_wall_seconds,
            worker_solver_seconds = worker_solver_seconds,
            worker_overhead_seconds = worker_overhead_seconds,
            cut_seconds = cut_seconds,
            total_seconds = iteration_seconds,
        )

        if output
            println(
                "Benders iteration=$(optimizer.current_iter) ",
                "MP=$(round(root_solve_time; digits=3))s ",
                "SP=$(round(worker_batch_wall_seconds; digits=3))s ",
                "LB=$(round(lower_bound; digits=6)) ",
                "UB=$(round(optimizer.best_upper_bound; digits=6)) ",
                "gap=$(round(gap; digits=8)) ",
                "cuts=$(round(cut_seconds; digits=3))s ",
                "total=$(round(iteration_seconds; digits=3))s",
            )
            flush(stdout)
        end

        run_gc && GC.gc()

        if gap < optimizer.tol
            optimizer.objective_value = optimizer.best_upper_bound
            optimizer.status = PlasmoBenders.MOI.OPTIMAL
            println("Optimal Solution Found!")
            return nothing
        end

        if sum(optimizer.time_iterations) > optimizer.time_limit
            optimizer.objective_value = upper_bound
            optimizer.status = PlasmoBenders.MOI.TIME_LIMIT
            return nothing
        end
    end

    optimizer.objective_value = optimizer.best_upper_bound
    optimizer.status = PlasmoBenders.MOI.ITERATION_LIMIT
    return nothing
end
