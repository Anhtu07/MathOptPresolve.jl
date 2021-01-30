"""
Perform coefficient strengthening on each row and on each integer variable.

In particular, for the i-th constraints of the form
aᵢ x ⩽ bᵢ and let xⱼ be a integer/binary variable
If aᵢⱼ ⩾ d = bᵢ - Mᵢⱼ - aᵢⱼ (uⱼ - 1) > 0
where Mᵢⱼ is maximal activity of the i-th row without considering xⱼ
and uⱼ is upper bound of xⱼ, then we transform
aᵢⱼ <- aᵢⱼ - d
bᵢ <- bᵢ - duⱼ .

A similar update rule is applied for the constraints of the form cᵢ ⩽ aᵢ x.

In case the constraint is ranged, i.e, cᵢ ⩽ aᵢ x ⩽ bᵢ, no coefficient strengthening is performed.

The new coefficients are stored by updating ps.pb0 .
If some coefficient is reduced to 0, it is kept as 0 in both ps.pb0.arows and ps.pb0.acols,
and the number of nonzeros in each row/column is updated.

If a row/column is reduced to 0 after this step, it will be set to be inactive.
"""

function maximal_activity(row::Row{T}, ucol::Vector{T}, lcol::Vector{T})::T where {T}
    sup = zero(T)

    for (j, aij) in zip(row.nzind, row.nzval)
        if aij > zero(T)
            sup += aij*ucol[j]
        elseif aij < zero(T)
            sup += aij*lcol[j]
        end
    end
    return T(sup)
end

function minimal_activity(row::Row{T}, ucol::Vector{T}, lcol::Vector{T})::T where {T}
    inf = zero(T)

    for (j, aij) in zip(row.nzind, row.nzval)
        if aij > zero(T)
            inf += aij*lcol[j]
        elseif aij < zero(T)
            inf += aij*ucol[j]
        end
    end
    return T(inf)
end

function upperbound_strengthening(ps::PresolveData{T}, i::Int, j_index::Int, j::Int, max_act) where {T}
    # perform coef strengthening for one constraints of the from a'x <= u
    row = ps.pb0.arows[i]
    a = row.nzval
    new_bound = ps.urow[i]
    new_coef = a[j_index]
    if a[j_index] > 0
        d = new_bound - max_act - a[j_index]*(ps.ucol[j]-1)
        if a[j_index] >= d > 0
            new_coef = new_coef - d
            new_bound -= d*ps.ucol[j]
        end
    elseif a[j_index] < 0
        d = new_bound - max_act - a[j_index]*(ps.lcol[j]+1)
        if -a[j_index] >= d > 0
            new_coef = new_coef + d
            new_bound += d*ps.lcol[j]
        end
    end
    return new_coef, new_bound
end

function lowerbound_strengthening(ps::PresolveData{T}, i::Int, j_index::Int, j::Int, min_act) where {T}
    # perform coef strengthening for one constraints of the from l < = a'x
    row = ps.pb0.arows[i]
    a = row.nzval
    new_bound = ps.lrow[i]
    new_coef = a[j_index]
    if a[j_index] > 0
        d = -new_bound + min_act + a[j_index]*(ps.lcol[j]+1)
        if a[j_index] >= d > 0
            new_coef = a[j_index] - d
            new_bound -= d*ps.lcol[j]
        end
    elseif a[j_index] < 0
        d = -new_bound + min_act + a[j_index]*(ps.ucol[j]-1)
        if -a[j_index] >= d > 0
            new_coef = a[j_index] + d
            new_bound += d*ps.ucol[j]
        end
    end
    return new_coef, new_bound
end

function zero_coefficient_strengthening!(ps::PresolveData{T}) where {T}
    # perform coefficient stregthening but if there is a coefficient is reduced to 0
    # it is still kept in the ps.pb0.arows and ps.pb0.acols

    # keep track of index for each var fo update ps.acols
    # use this to find which index of ps.pb0.acols[i].nzval to update
    i_index = zeros(Int, ps.pb0.nvar)

    for i in 1:ps.pb0.ncon

        lrow = ps.lrow[i]
        urow = ps.urow[i]
        if isfinite(lrow) && isfinite(urow) #skip ranged constraints
            continue
        end

        row = ps.pb0.arows[i]
        if all(ps.var_types[row.nzind] .== CONTINUOUS) # at least 1 integer
            continue
        end

        sup = maximal_activity(row, ps.ucol, ps.lcol)
        inf = minimal_activity(row, ps.ucol, ps.lcol)

        j_index = 0 # keep track of index of variable j in row.nzind & row.nzval
        for j in row.nzind
            j_index += 1
            i_index[j] += 1
            if ps.var_types[j] == CONTINUOUS || !ps.colflag[j]
                continue
            else
                coef = row.nzval[j_index]

                if isfinite(urow)
                    if coef > 0
                        max_act = sup - coef * ps.ucol[j] # maximal activity of every variables except j
                    else
                        max_act = sup - coef * ps.lcol[j]
                    end
                    new_coef, new_bound = upperbound_strengthening(ps, i, j_index, j, max_act)
                    # update problem
                    row.nzval[j_index] = new_coef
                    ps.pb0.acols[j].nzval[i_index[j]] = new_coef
                    ps.urow[i] = new_bound
                    #update nonzero
                    if new_coef == 0
                        ps.nzrow[i] -= 1
                        ps.nzcol[j] -= 1
                    end
                    #update sup
                    if coef > 0
                        sup -= (coef - new_coef) * ps.ucol[j]
                    else
                        sup -= (coef - new_coef) * ps.lcol[j]
                    end
                elseif isfinite(lrow)
                    if coef > 0
                        min_act = inf - coef * ps.lcol[j] # minimal activity of every variables except j
                    else
                        min_act = inf - coef * ps.ucol[j]
                    end
                    new_coef, new_bound = lowerbound_strengthening(ps, i, j_index, j, min_act)
                    #update problem
                    row.nzval[j_index] = new_coef
                    ps.pb0.acols[j].nzval[i_index[j]] = new_coef
                    ps.lrow[i] = new_bound
                    #update nonzero
                    if new_coef == 0
                        ps.nzrow[i] -= 1
                        ps.nzcol[j] -= 1
                    end
                    #update inf
                    if coef > 0
                        inf -= (coef - new_coef) * ps.lcol[j]
                    else
                        inf -= (coef - new_coef) * ps.ucol[j]
                    end
                end
            end
        end
    end
    return nothing
end
