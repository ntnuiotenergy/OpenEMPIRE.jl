const _BOUNDED_WORKER_FORWARD_CACHE = Dict{Int, Tuple{Any, Any}}()

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
            (
                index = job.index,
                darray = initialize_worker_cache ? job.darray : nothing,
                var_copies = initialize_worker_cache ? job.var_copies : nothing,
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

            JuMP.fix.(lvar_copies, job.last_primals, force = true)
            t_solve = @elapsed JuMP.optimize!(lgraph)

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
            optimizer.primal_iters[object] =
                hcat(optimizer.primal_iters[object], primals)
        end
        optimizer.last_solutions[root_object] =
            PlasmoBenders._get_object_last_solutions(root_object)

        @sync for (_, objects) in worker_groups
            @async begin
                results = _optimize_remote_graph_forward_batch(
                    optimizer,
                    objects,
                    initialize_worker_cache = optimizer.current_iter == 0,
                )

                for (index, feasible, objective, duals, solve_time) in results
                    object = optimizer.solve_order[index]

                    optimizer.time_subproblem_solves += solve_time
                    optimizer.feasibility_map[object] = feasible
                    optimizer.subgraph_objectives[object] =
                        feasible ? objective : Inf

                    optimizer.dual_iters[object] = hcat(
                        optimizer.dual_iters[object],
                        duals,
                    )
                    push!(optimizer.phis[object], objective)
                end
            end
        end

        upper_bound = sum(
            optimizer.subgraph_objectives[object]
            for object in optimizer.solve_order
        )
        if upper_bound < optimizer.best_upper_bound ||
           isempty(optimizer.upper_bounds)
            optimizer.best_upper_bound = upper_bound
        end

        PlasmoBenders._add_Benders_cuts!(optimizer)

        push!(optimizer.lower_bounds, lower_bound)
        push!(optimizer.upper_bounds, upper_bound)
        push!(optimizer.time_iterations, time() - root_start)
        optimizer.current_iter += 1

        gap = if optimizer.best_upper_bound != 0
            abs((optimizer.best_upper_bound - lower_bound) / optimizer.best_upper_bound)
        else
            abs(optimizer.best_upper_bound - lower_bound)
        end

        if output && (optimizer.current_iter == 1 || optimizer.current_iter % 20 == 0)
            println(
                "Iteration ",
                optimizer.current_iter,
                ", gap ",
                gap,
                ", lower bound ",
                lower_bound,
                ", upper bound ",
                optimizer.best_upper_bound,
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
