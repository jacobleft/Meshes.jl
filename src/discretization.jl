# ------------------------------------------------------------------
# Licensed under the MIT License. See LICENSE in the project root.
# ------------------------------------------------------------------

"""
    DiscretizationMethod

A method for discretizing geometries into meshes.
"""
abstract type DiscretizationMethod end

"""
    discretize(geometry, method)

Discretize `geometry` with discretization `method`.
"""
function discretize end

"""
    BoundaryDiscretizationMethod

A method for discretizing geometries based on their boundary.
"""
abstract type BoundaryDiscretizationMethod <: DiscretizationMethod end

"""
    discretizewithin(boundary, method)

Discretize geometry within `boundary` with boundary discretization `method`.
"""
function discretizewithin end

discretize(geometry, method::BoundaryDiscretizationMethod) =
  discretizewithin(boundary(geometry), method)

function discretize(polygon::Polygon{Dim,T}, method::BoundaryDiscretizationMethod) where {Dim,T}
  # build bridges in case the polygon has holes,
  # i.e. reduce to a single outer boundary
  chain, dups = bridge(unique(polygon), width=2atol(T))

  # discretize using outer boundary
  mesh = discretizewithin(chain, method)

  if isempty(dups)
    # nothing to be done, return mesh
    mesh
  else
    # remove duplicate vertices
    points = vertices(mesh)
    for (i, j) in dups
      points[i] = centroid(Segment(points[i], points[j]))
    end
    repeated = sort(last.(dups))
    deleteat!(points, repeated)

    # adjust connectivities
    elems = elements(topology(mesh))
    twin  = Dict(reverse.(dups))
    rrep  = reverse(repeated)
    einds = map(elems) do elem
      inds = indices(elem)
      [get(twin, ind, ind) for ind in inds]
    end
    for inds in einds
      for r in rrep
        for i in 1:length(inds)
          inds[i] > r && (inds[i] -= 1)
        end
      end
    end
    connec = connect.(Tuple.(einds))

    # return mesh without duplicates
    SimpleMesh(points, connec)
  end
end

discretize(multi::Multi, method::BoundaryDiscretizationMethod) =
  mapreduce(geom -> discretize(geom, method), merge, multi)

function discretizewithin(chain::Chain{3}, method::BoundaryDiscretizationMethod)
  # collect vertices to get rid of static containers
  points = vertices(chain) |> collect

  # project points on 2D plane of maximum variance
  projected = proj2D(points)

  # discretize within 2D chain with given method
  chain2D = Chain([projected; first(projected)])
  mesh    = discretizewithin(chain2D, method)

  # return mesh with original points
  SimpleMesh(points, topology(mesh))
end

"""
    simplexify(object)

Discretize `object` into simplices using an
appropriate discretization method.

### Notes

This function is sometimes called "triangulate"
when the `object` has parametric dimension 2.
"""
function simplexify end

# fallback method for all geometries
simplexify(geometry) = discretize(geometry, RegularDiscretization(50))

# -----------------------
# PARAMETRIC DIMENSION 1
# -----------------------

simplexify(box::Box{1}) = SimpleMesh(vertices(box), GridTopology(1))

simplexify(seg::Segment) = SimpleMesh(vertices(seg), GridTopology(1))

function simplexify(chain::Chain)
  np = npoints(chain)
  ip = isperiodic(chain)

  points = collect(vertices(chain))
  topo   = GridTopology((np-1,), ip)

  SimpleMesh(points, topo)
end

# -----------------------
# PARAMETRIC DIMENSION 2
# -----------------------

simplexify(box::Box{2}) = discretize(box, FanTriangulation())

simplexify(tri::Triangle) = discretize(tri, FanTriangulation())

simplexify(quad::Quadrangle) = discretize(quad, FanTriangulation())

simplexify(ngon::Ngon) = discretize(ngon, Dehn1899())

simplexify(poly::PolyArea) = discretize(poly, FIST())

simplexify(multi::Multi) = mapreduce(simplexify, merge, multi)

function simplexify(mesh::Mesh)
  points = vertices(mesh)
  elems  = elements(mesh)
  topo   = topology(mesh)
  connec = elements(topo)

  # initialize vector of global indices
  ginds = Vector{Int}[]

  # simplexify each element and append global indices
  for (e, c) in zip(elems, connec)
    # simplexify single element
    mesh′   = simplexify(e)
    topo′   = topology(mesh′)
    connec′ = elements(topo′)

    # global indices
    inds = indices(c)

    # convert from local to global indices
    einds = [[inds[i] for i in indices(c′)] for c′ in connec′]

    # save global indices
    append!(ginds, einds)
  end

  # new connectivities
  newconnec = connect.(Tuple.(ginds), Triangle)

  SimpleMesh(points, newconnec)
end

simplexify(sphere::Sphere{3}) =
  discretize(sphere, RegularDiscretization(50)) |> simplexify

simplexify(ball::Ball{2}) =
  discretize(ball, RegularDiscretization(50)) |> simplexify

simplexify(cylsurf::CylinderSurface) =
  discretize(cylsurf, RegularDiscretization(50, 2)) |> simplexify

# ----------------
# IMPLEMENTATIONS
# ----------------

include("discretization/fan.jl")
include("discretization/regular.jl")
include("discretization/fist.jl")
include("discretization/dehn.jl")
