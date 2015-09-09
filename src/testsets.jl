# All tests belong to a test set. There is a default, task-level
# test set that throws on first failure. Users can wrap their tests in
# nested test sets to achieve other behaviours like not failing
# immediately or writing test results in special formats.

#-----------------------------------------------------------------------
# The AbstractTestSet interface is defined by two methods:
# record(AbstractTestSet, Result)
#   Called by do_test after a test is evaluated
# finish(AbstractTestSet)
#   Called after the test set has been popped from the test set stack
abstract AbstractTestSet


#-----------------------------------------------------------------------
# We provide a simple fallback test set that throws immediately on a
# failure, but otherwise doesn't do much
immutable DefaultTestSet <: AbstractTestSet
end
default_testset = DefaultTestSet()

# Records nothing, and throws any immediately error whenever an error
# or failure occurs. Does nothing for passing tests.
record(ts::DefaultTestSet, t::Pass) = t
function record(ts::DefaultTestSet, t::Union(Fail,Error))
    println(t)
    error("There was an error during testing")
end
# Does nothing
finish(ts::DefaultTestSet) = nothing


#-----------------------------------------------------------------------
# We provide a basic test set that stores results, and doesn't throw
# any exceptions until the end of the test set.
include("basictestset.jl")


#-----------------------------------------------------------------------
"""
@testset "description" option1=val1 begin ... end
@testset "description" begin ... end
@testset begin ... end

Starts a new test set, by default using the BasicTestSet. If using the
BasicTestSet, the test results will be recorded and displayed at the end
of the test set. If there are any failures, an exception will be thrown.
"""
macro testset(args...)
    options = Dict{Symbol, Any}()
    desc = ""
    # Parse arguments to do determine if any options passed in
    if length(args) == 0
        error("@testset requires a test expression")
    else
        # assume the last (and possibly only) argument is the test expression
        tests = args[end]
        for arg in args[1:end-1]
            if isa(arg, String)
                desc = arg
            elseif isa(arg, Expr) && arg.head == :(=)
                # we have an assignment. assume it's setting an argument
                options[arg.args[1]] = eval(arg.args[2])
            else
                error("Unexpected argument $arg to @testset")
            end
        end
    end

    ts = gensym()
    quote
        $ts = BasicTestSet($desc; $options...)
        add_testset($ts)
        $(esc(tests))
        pop_testset()
        finish($ts)
    end
end



"""
@testloop "description \$v" for v in (...) ... end
@testloop for x in (...), y in (...) ... end

Starts a new test set, for each iteration of the loop. The description string accepts interpolation from the loop indices. If no description is provided, one is constructed based on the variables.
"""
macro testloop(args...)
    # Parse arguments to do determine if any options passed in
    if length(args) == 2
        # Looks like description format
        desc, testloop = args        
        isa(desc,String) || (isa(desc,Expr) && desc.head == :string) || error("Unexpected argument to @testloop")
        isa(testloop,Expr) && testloop.head == :for || error("Unexpected argument to @testloop")

    elseif length(args) == 1
        # No description provided
        testloop = args[1]
        isa(testloop,Expr) && testloop.head == :for || error("Unexpected argument to @testloop")
        loopvars = testloop.args[1]
        if loopvars.head == :(=)
            # 1 variable
            v = loopvars.args[1]
            desc = Expr(:string,"$v = ",v)
        else
            # multiple variables
            v = loopvars.args[1].args[1]
            desc = Expr(:string,"$v = ",v) # first variable
            for l = loopvars.args[2:end]
                v = l.args[1]
                push!(desc.args,", $v = ")
                push!(desc.args,v)
            end
        end
    elseif length(args) >= 3
        error("Too many arguments to @testloop")
    else
        error("Too few arguments to @testloop")
    end
    
    ts = gensym()
    tests = testloop.args[2]  
    blk = quote
        $ts = BasicTestSet($(esc(desc)))
        add_testset($ts)
        $(esc(tests))
        pop_testset()
        finish($ts)
    end
    Expr(:for,esc(testloop.args[1]),blk)
end


#-----------------------------------------------------------------------
# Define various helper methods for test sets
"""
get_testset()

Retrieve the active test set from the task's local storage. If no
test set is active, use the fallback default test set.
"""
function get_testset()
    testsets = get(task_local_storage(), :__BASETESTNEXT__, AbstractTestSet[])
    return length(testsets) == 0 ? default_testset : testsets[end]
end

"""
add_testset(ts::AbstractTestSet)

Adds the test set to the task_local_storage.
"""
function add_testset(ts::AbstractTestSet)
    testsets = get(task_local_storage(), :__BASETESTNEXT__, AbstractTestSet[])
    push!(testsets, ts)
    setindex!(task_local_storage(), testsets, :__BASETESTNEXT__)
end

"""
pop_testset()

Pops the last test set added to the task_local_storage. If there are no
active test sets, returns the default test set.
"""
function pop_testset()
    testsets = get(task_local_storage(), :__BASETESTNEXT__, AbstractTestSet[])
    ret = length(testsets) == 0 ? default_testset : pop!(testsets)
    setindex!(task_local_storage(), testsets, :__BASETESTNEXT__)
    return ret
end

"""
get_testset_depth()

Returns the number of active test sets, not including the defaut test set
"""
function get_testset_depth()
    testsets = get(task_local_storage(), :__BASETESTNEXT__, AbstractTestSet[])
    return length(testsets)
end
