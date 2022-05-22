module vtypechoice;

public import vtypechoice.result;
public import vtypechoice.optional;
public import std.sumtype;


  // ==============================
 // # Result to Optional interop #
// ==============================

auto optional(T, E)(auto ref scope Result!(T, E) result)
{
	return result.match!(
		(in Err!E) => Optional!T.none(),
		(in T ok) => Optional!T.some(ok),
	);
}

///
version(vtypechoice_unittest)
@safe pure nothrow @nogc unittest
{
	assert(Result!int.ok(3).optional == 3.some);
	assert(Result!int.err("failure").optional == none);
}


  // ==============================
 // # Optional to Result interop #
// ==============================

auto result(E, T)(auto ref scope Optional!T optional, E err)
{
	return optional.match!(
		(in None _) => Result!(T, E).err(err),
		(in T value) => Result!(T, E).ok(value),
	);
}

///
version(vtypechoice_unittest)
@safe pure nothrow @nogc unittest
{
	assert(Optional!int.some(3).result("failure") == 3.ok);
	assert(Optional!int.none.result("failure") == "failure".err);
}


auto result(alias pred, T)(auto ref scope Optional!T optional)
{
	static if (isErr!(typeof(pred())))
	{
		alias R = Result!(T, typeof(pred().get));
		enum call = "pred().get";
	}
	else
	{
		alias R = Result!(T, typeof(pred()));
		enum call = "pred()";
	}

	return optional.match!(
		function R (in None _) => mixin(call).err,
		function R (in T value) => value.ok,
	);
}

///
version(vtypechoice_unittest)
@safe pure nothrow @nogc unittest
{
	assert(Optional!int.some(3).result!(() => "failure") == 3.ok);
	assert(Optional!int.none.result!(() => "failure") == "failure".err);
	assert(Optional!int.none.result!(() => "failure".err) == "failure".err);
}
