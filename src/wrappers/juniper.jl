@params struct JuniperIpoptOptions
    nt::NamedTuple
    subsolver_options
    first_order::Bool
end
function JuniperIpoptOptions(;
    first_order = true, subsolver_options = IpoptOptions(first_order = first_order), kwargs...,
)
    first_order = !hasproperty(subsolver_options.nt, :hessian_approximation) ||
        subsolver_options.nt.hessian_approximation == "limited-memory"
    return JuniperIpoptOptions((; kwargs...), subsolver_options, first_order)
end

@params mutable struct JuniperIpoptWorkspace <: Workspace
    model::Model
    problem::JuMPProblem
    x0::AbstractVector
    options::JuniperIpoptOptions
    counter::Base.RefValue{Int}
end
function JuniperIpoptWorkspace(
    model::Model, x0::AbstractVector = getinit(model);
    options = JuniperIpoptOptions(), kwargs...,
)
    nt1 = options.subsolver_options.nt
    subsolver_options = map(keys(nt1)) do k
        string(k) => nt1[k]
    end
    nl_solver = JuMP.optimizer_with_attributes(Ipopt.Optimizer, Dict(subsolver_options)...)
    nt2 = options.nt
    solver_options = map(nt2) do k
        string(k) => nt2[k]
    end
    optimizer = JuMP.optimizer_with_attributes(
        Juniper.Optimizer, "nl_solver" => nl_solver, Dict(solver_options)...,
    )
    problem, counter = get_jump_problem(
        model, x0; first_order = options.first_order, optimizer = optimizer,
    )
    return JuniperIpoptWorkspace(model, problem, x0, options, counter)
end
@params struct JuniperIpoptResult
    minimizer
    minimum
    problem
    status
    fcalls::Int
end

function optimize!(workspace::JuniperIpoptWorkspace)
    @unpack problem, options, counter = workspace
    counter[] = 0
    jump_problem = workspace.problem
    jump_model = jump_problem.model
    moi_model = jump_model.moi_backend
    MOI.optimize!(moi_model)
    minimizer = MOI.get(moi_model, MOI.VariablePrimal(), jump_problem.vars)
    objval = MOI.get(moi_model, MOI.ObjectiveValue())
    term_status = MOI.get(moi_model, MOI.TerminationStatus())
    primal_status = MOI.get(moi_model, MOI.PrimalStatus())
    return JuniperIpoptResult(
        minimizer, objval, problem, (term_status, primal_status), counter[],
    )
end

struct JuniperIpoptAlg{O}
    options::O
end
JuniperIpoptAlg(; kwargs...) = JuniperIpoptAlg(kwargs)

function Workspace(model::AbstractModel, optimizer::JuniperIpoptAlg, args...; kwargs...,)
    return JuniperIpoptWorkspace(model, args...; kwargs...)
end
