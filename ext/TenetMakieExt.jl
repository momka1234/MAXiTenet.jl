module TenetMakieExt

using Tenet
using Tenet: AbstractTensorNetwork
using Combinatorics: combinations
using Graphs
using Makie

using GraphMakie

"""
    plot(tn::TensorNetwork; kwargs...)
    plot!(f::Union{Figure,GridPosition}, tn::TensorNetwork; kwargs...)
    plot!(ax::Union{Axis,Axis3}, tn::TensorNetwork; kwargs...)

Plot a [`TensorNetwork`](@ref) as a graph.

# Keyword Arguments

  - `labels` If `true`, show the labels of the tensor indices. Defaults to `false`.
  - The rest of `kwargs` are passed to `GraphMakie.graphplot`.
"""
function Makie.plot(@nospecialize tn::AbstractTensorNetwork; kwargs...)
    f = Figure()
    ax, p = plot!(f[1, 1], tn; kwargs...)
    return Makie.FigureAxisPlot(f, ax, p)
end

# NOTE this is a hack! we did it in order not to depend on NetworkLayout but can be unstable
__networklayout_dim(x) = typeof(x).super.parameters |> first

function Makie.plot!(f::Union{Figure,GridPosition}, @nospecialize tn::AbstractTensorNetwork; kwargs...)
    ax = if haskey(kwargs, :layout) && __networklayout_dim(kwargs[:layout]) == 3
        Axis3(f[1, 1])
    else
        ax = Axis(f[1, 1])
        ax.aspect = DataAspect()
        ax
    end

    hidedecorations!(ax)
    hidespines!(ax)

    p = plot!(ax, tn; kwargs...)

    return Makie.AxisPlot(ax, p)
end

function Makie.plot!(ax::Union{Axis,Axis3}, @nospecialize tn::AbstractTensorNetwork; labels = false, kwargs...)
    hypermap = Tenet.hyperflatten(tn)
    tn = transform(tn, Tenet.HyperindConverter)

    tensormap = IdDict(tensor => i for (i, tensor) in enumerate(tensors(tn)))

    # TODO how to mark multiedges? (i.e. parallel edges)
    graph = SimpleGraph([
        Edge(map(Base.Fix1(getindex, tensormap), tensors)...) for (_, tensors) in tn.indexmap if length(tensors) > 1
    ])

    # TODO recognise `copytensors` by using `DeltaArray` or `Diagonal` representations
    copytensors = findall(tensor -> any(flatinds -> issetequal(inds(tensor), flatinds), keys(hypermap)), tensors(tn))
    ghostnodes = map(inds(tn, :open)) do index
        # create new ghost node
        add_vertex!(graph)
        node = nv(graph)

        # connect ghost node
        tensor = only(tn.indexmap[index])
        add_edge!(graph, node, tensormap[tensor])

        return node
    end

    # configure graphics
    # TODO refactor hardcoded values into constants
    kwargs = Dict{Symbol,Any}(kwargs)

    if haskey(kwargs, :node_size)
        append!(kwargs[:node_size], zero(ghostnodes))
    else
        kwargs[:node_size] = map(1:nv(graph)) do i
            i ∈ ghostnodes ? 0 : max(15, log2(length(tensors(tn)[i])))
        end
    end

    if haskey(kwargs, :node_marker)
        append!(kwargs[:node_marker], fill(:circle, length(ghostnodes)))
    else
        kwargs[:node_marker] = map(i -> i ∈ copytensors ? :diamond : :circle, 1:nv(graph))
    end

    if haskey(kwargs, :node_color)
        kwargs[:node_color] = vcat(kwargs[:node_color], fill(:black, length(ghostnodes)))
    else
        kwargs[:node_color] = map(1:nv(graph)) do v
            v ∈ copytensors ? Makie.to_color(:black) : Makie.RGBf(240 // 256, 180 // 256, 100 // 256)
        end
    end

    get!(kwargs, :node_attr, (colormap = :viridis, strokewidth = 2.0, strokecolor = :black))

    # configure labels
    labels == true && get!(kwargs, :elabels) do
        opentensors = findall(t -> !isdisjoint(inds(t), inds(tn, :open)), tensors(tn))
        opencounter = IdDict(tensor => 0 for tensor in opentensors)

        map(edges(graph)) do edge
            # case: open edge
            if any(∈(ghostnodes), [src(edge), dst(edge)])
                notghost = src(edge) ∈ ghostnodes ? dst(edge) : src(edge)
                inds = Tenet.inds(tn, :open) ∩ Tenet.inds(tensors(tn)[notghost])
                opencounter[notghost] += 1
                return inds[opencounter[notghost]] |> string
            end

            # case: hyperedge
            if any(∈(copytensors), [src(edge), dst(edge)])
                i = src(edge) ∈ copytensors ? src(edge) : dst(edge)
                # hyperindex = filter(p -> isdisjoint(inds(tensors)[i], p[2]), hypermap) |> only |> first
                hyperindex = hypermap[Tenet.inds(tensors(tn)[i])]
                return hyperindex |> string
            end

            return join(Tenet.inds(tensors(tn)[src(edge)]) ∩ Tenet.inds(tensors(tn)[dst(edge)]), ',')
        end
    end
    get!(() -> repeat([:black], ne(graph)), kwargs, :elabels_color)
    get!(() -> repeat([17], ne(graph)), kwargs, :elabels_textsize)

    # plot graph
    graphplot!(ax, graph; kwargs...)
end

end
