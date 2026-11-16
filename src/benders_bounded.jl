function run_benders_by_worker!(optimizer; output = true, run_gc = false)
    optimizer.is_MIP &&
        error("run_benders_by_worker! currently supports linear Benders models only")

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

        worker_groups = Dict{Int, Vector{Tuple{Int, Any}}}()
        for index in 2:length(optimizer.solve_order)
            object = optimizer.solve_order[index]
            push!(
                get!(worker_groups, object.worker, Tuple{Int, Any}[]),
                (index, object),
            )
        end

        @sync for (_, objects) in worker_groups
            @async begin
                for (index, object) in objects
                    feasible, objective, duals, solve_time =
                        PlasmoBenders._optimize_remote_graph_forward(
                            optimizer,
                            object,
                            index,
                        )

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
