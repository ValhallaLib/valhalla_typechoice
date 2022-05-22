module vtypechoice.result;

import core.lifetime : forward;
import std.sumtype;

alias isResult(T) = imported!"std.traits".isInstanceOf!(Result, T);
alias isOk(T) = imported!"std.traits".isInstanceOf!(Ok, T);
alias isErr(T) = imported!"std.traits".isInstanceOf!(Err, T);

struct Result(T, E = string)
{
	import core.lifetime : forward;
	import std.traits : CopyConstness, isInstanceOf, Unqual;
	import std.meta : AliasSeq, IndexOf = staticIndexOf, Map = staticMap;


	alias Ok = .Ok!T;
	alias Err = .Err!E;


	static ok(U)(U ok)
	{
		static if (.isOk!U || .isErr!U)
		{
			static assert(isResult!T, "Cannot convert Ok!("~U.stringof~") to "~Ok.stringof);
			// lets perform: Result!(Result!int).ok(Ok!(Ok!int)(Ok!int(3));
			static if (.isOk!U)
				CopyConstness!(U, Result) res = { st: Ok(T.ok(ok.get)) };
			else
				CopyConstness!(U, Result) res = { st: Ok(T.err(ok.get)) };
		}
		else static if (isInstanceOf!(U, CopyConstness!(U, Ok)))
			CopyConstness!(U, Result) res = { st: ok };
		else
			CopyConstness!(U, Result) res = { st: (CopyConstness!(U, Ok)(ok)) };

		return res;
	}


	static err(U)(U err)
	{
		static if (.isOk!U || .isErr!U)
		{
			static assert(isResult!T, "Cannot convert Ok!("~U.stringof~") to "~Ok.stringof);
			// lets perform: Result!(Result!int).ok(Ok!(Ok!int)(Ok!int(3));
			static if (.isOk!U)
				CopyConstness!(U, Result) res = { st: Ok(T.ok(ok.get)) };
			else
				CopyConstness!(U, Result) res = { st: Ok(T.err(ok.get)) };
		}
		else static if (isInstanceOf!(U, CopyConstness!(U, Err)))
			CopyConstness!(U, Result) res = { st: err };
		else
			CopyConstness!(U, Result) res = { st: CopyConstness!(U, Err)(err) };

		return res;
	}


	bool opEquals(in Result rhs) scope const
	{
		return st == rhs.st;
	}


	bool opEquals(U)(in U rhs) scope const
	{
		// allow comparing only with Ok or Err
		// turning opEquals into a template forces it to never cast to alias this
		// since both Ok and Err alias to their template parameter type,
		// restricting the opEquals' parameter to Ok or Err would not evaluate
		// correctly if for example Ok!(Ok!T) was provided, as it would cast it
		// to Ok!T making it the wrong comparison to perform
		enum errmsg = "Cannot compare "~U.stringof~" with "~Result.stringof;
		static assert(.isOk!U || .isErr!U, errmsg);

		static if (.isOk!U)
		{
			// ensure this is a valid type comparison
			// fail here for a better error message, otherwise it'll fail with
			// a generic SumType's message
			static assert(__traits(compiles, T.init == rhs.get), errmsg);
			return st.match!(
				(in Err _) => false,
				(in T ok) => ok == rhs.get,
			);
		}
		else static if(.isErr!U) // not needed, but kept for clarity
		{
			// ensure this is a valid type comparison
			// fail here for a better error message, otherwise it'll fail with
			// a generic SumType's message
			static assert(__traits(compiles, E.init == rhs.get), errmsg);
			return st.match!(
				(in Ok _) => false,
				(in E err) => err == rhs.get,
			);
		}
		else static assert(0); // we know this never happens
	}


	// FIXME: prohibit implicit casting
	auto ref opAssign(U)(U rhs) scope return
		if (.isOk!U)
	{
		enum errmsg = "Cannot assign "~U.stringof~" to "~Result.stringof;
		static assert(__traits(compiles, () { T ok; ok = rhs.get; }), errmsg);

		st = rhs;

		return this;
	}


	auto ref opAssign(U)(U rhs) scope return
		if (.isErr!U)
	{
		enum errmsg = "Cannot assign "~U.stringof~" to "~Result.stringof;

		static assert(__traits(compiles, () { E err; err = rhs.get; }), errmsg);

		st = rhs;

		return this;
	}


	bool isErr() scope const
	{
		return st.match!((in value) => .isErr!(typeof(value)));
	}

	bool isOk() scope const
	{
		return !isErr();
	}


	  // ===================
	 // # Result as range #
	// ===================

	alias back = front;
	alias empty = isErr;

	auto ref inout(T) front() inout scope return
	{
		return this.unwrap();
	}

	alias length = isOk;


	alias opDollar(size_t dim : 0) = length;

	ref opIndex() scope return
	{
		return this;
	}

	ref inout(T) opIndex(size_t index) scope inout return
		in (index < length)
	{
		return this.unwrap();
	}

	ref opIndex(size_t[2] dim) scope return
		in (dim[0] <= dim[1])
		in (dim[1] <= length)
	{
		return this;
	}

	size_t[2] opSlice(size_t dim : 0)(size_t start, size_t end) scope return
	{
		return [start, end];
	}


	alias popBack = popFront;
	void popFront() scope { st = Err.init; }


	inout(Result) save() scope inout { return this; }


	SumType!(Ok, Err) st;
	alias st this;
}

///
version(vtypechoice_unittest)
@safe pure nothrow @nogc unittest
{
	alias R = Result!int;

	assert(R.ok(3) == Ok!int(3));
	assert(R.err("failure") == Err!string("failure"));

	assert(R.ok(3).match!(
		(Err!string) => false, // use Ok/Err to match
		(int) => true,         // or use the underlying type to match
	));

	assert(R.init == R.init);
	assert(R.ok(0) != R.err(""));


	static assert(!__traits(compiles, R.init = Ok!(Ok!int).init));
	static assert(!__traits(compiles, R.init = Ok!short.init)); // TODO: should this be allowed?

	() @trusted
	{
		assert((R.ok(3) = 10.ok) == 10.ok);
		assert((R.ok(3) = "failure".err) == "failure".err);
	}
	();
}


struct Ok(T)
{
	T get;
	alias get this;
}

auto ok(T, string prettyFun = __PRETTY_FUNCTION__, string funName = __FUNCTION__)(T value)
{
	enum untilFunName = ()
	{
		for (size_t i; i + funName.length < prettyFun.length; i++)
			if (prettyFun[i .. i + funName.length] == funName) return i;
		return 0;
	} ();

	static if (is(mixin(prettyFun[0 .. untilFunName]) Type == Result!Args, Args...))
		return Type.ok(value);
	else
		return Ok!T(value);
}

///
version(vtypechoice_unittest)
@safe pure nothrow @nogc unittest
{
	static assert(__traits(compiles, () => 10.ok));
	static assert(is(typeof(() { return 10.ok; } ()) == Ok!int));
	static assert(__traits(compiles, function Result!int() => 10.ok));
}



struct Err(T)
{
	T get;
	alias get this;
}

auto err(E, string prettyFun = __PRETTY_FUNCTION__, string funName = __FUNCTION__)(E value)
{
	enum untilFunName = ()
	{
		for (size_t i; i + funName.length < prettyFun.length; i++)
			if (prettyFun[i .. i + funName.length] == funName) return i;
		return 0;
	} ();

	static if (is(mixin(prettyFun[0 .. untilFunName]) Type == Result!Args, Args...))
		return Type.err(value);
	else
		return Err!E(value);
}

///
version(vtypechoice_unittest)
@safe pure nothrow @nogc unittest
{
	static assert(__traits(compiles, () => "failure".err));
	static assert(is(typeof(() { return "failure".err; } ()) == Err!string));

	static assert(__traits(compiles, function Result!int() => "failure".err));
}


  // ==================================
 // # Result's functional operations #
// ==================================

auto andThen(alias pred, T, E)(auto ref scope Result!(T, E) result)
	if (isResult!(typeof(pred(T.init))) && is(typeof(pred(T.init)).Types[1] == Err!E))
{
	alias Type = imported!"std.traits".TemplateArgsOf!(typeof(pred(T.init)).Types[0]);

	return result.match!(
		(in Err!E err) => Result!(Type, E).err(err.get),
		(in T ok) => pred(ok),
	);
}

///
version(vtypechoice_unittest)
@safe pure nothrow @nogc unittest
{
	alias R = Result!int;
	assert(R.err("failure").andThen!(i => R.ok(i + 3)) == "failure".err);
	assert(R.ok(7).andThen!(i => R.ok(i + 3)) == 10.ok);
}


auto andThen(alias pred, T, E)(auto ref scope Result!(T, E) result)
	if (isOk!(typeof(pred(T.init))))
{
	alias Type = imported!"std.traits".TemplateArgsOf!(typeof(pred(T.init)))[0];

	return result.match!(
		(in Err!E err) => Result!(Type, E).err(err.get),
		(in T ok) { Result!(Type, E) res = { st: (pred(ok)) }; return res; },	);
}

auto andThen(alias pred, T, E)(auto ref scope Result!(T, E) result)
	if (is(typeof(pred(T.init)) == Err!E))
{
	alias Type = T;

	return result.match!(
		(in Err!E err) => Result!(Type, E).err(err.get),
		(in T ok) { Result!(Type, E) res = { st: (pred(ok)) }; return res; },
	);
}

///
version(vtypechoice_unittest)
@safe pure nothrow @nogc unittest
{
	alias R = Result!int;
	assert(R.err("failure").andThen!(i => ok(i + 3)) == "failure".err);
	assert(R.ok(7).andThen!(i => err("failure")) == "failure".err);
}


auto andThen(alias pred, T, E)(auto ref scope Result!(T, E) result)
	if (!isResult!(typeof(pred(T.init))) && !isOk!(typeof(pred(T.init))) && !isErr!(typeof(pred(T.init))))
{
	alias Type = typeof(pred(T.init));

	return result.match!(
		(in Err!E err) => Result!(Type, E).err(err.get),
		(in T ok) => Result!(Type, E).ok(pred(ok)),
	);
}

///
version(vtypechoice_unittest)
@safe pure nothrow @nogc unittest
{
	alias R = Result!int;
	assert(R.err("failure").andThen!(i => i + 3) == "failure".err);
	assert(R.ok(7).andThen!(i => i + 3) == 10.ok);
}


Result!(T, E) flatten(T, E)(auto ref scope Result!(Result!(T, E), E) result)
{
	return result.match!(
		(in Err!E err) => Result!(T, E).err(err.get),
		(in ok) => ok,
	);
}

///
version(vtypechoice_unittest)
@safe pure nothrow @nogc unittest
{
	alias R = Result!(Result!int);
	static assert(is(typeof(R.init.flatten()) == Result!int));

	assert(R.ok(3.ok).flatten() == 3.ok);
	assert(R.err("failure").flatten() == "failure".err);
}


template fmap(alias pred)
{
	auto fmap(T, E)(auto ref scope Result!(T, E) result)
	{
		alias Type = typeof(pred(T.init));
		return result.match!(
			(scope Err!E err) => Result!(Type, E).err(err.get),
			(scope T ok) => Result!(Type, E).ok(pred(ok)),
		);
	}
}

///
version(vtypechoice_unittest)
@safe pure nothrow @nogc unittest
{
	assert(Result!int.ok(3).fmap!(n => n + 7) == 10.ok);

	import std.algorithm: equal, map;
	import std.range : only;
	assert(Result!int.ok(3).only.map!(fmap!(n => n + 7)).equal(10.ok.only));
}


template fmapErr(alias pred)
{
	auto fmapErr(T, E)(auto ref scope Result!(T, E) result)
	{
		alias Type = typeof(pred(E.init));
		return result.match!(
			(ref scope Ok!T ok) => Result!(T, Type).ok(ok.get),
			(ref scope E err) => Result!(T, Type).err(pred(err)),
		);
	}
}

///
version(vtypechoice_unittest)
@safe pure nothrow @nogc unittest
{
	assert(Result!int.err("failure").fmapErr!(n => 0) == 0.err);

	import std.algorithm: equal, map;
	import std.range : only;
	assert(Result!int.err("failure").only.map!(fmapErr!(n => 0)).equal(0.err.only));
}


template fmapOr(alias pred)
{
	auto fmapOr(U, T, E)(auto ref scope Result!(T, E) result, auto ref scope U other)
	{
		// simmulate an implicit cast to pred's return type
		// if the return type is know to be ulong and an int is provided,
		// the program would compile and run if U was written as size_t
		// however, as it isn't, it would fail because !is(size_t : int)
		// by placing Ok!T first the return type will be pred's return type
		// forcing other to be implicitly castable to it
		return result.match!(
			(ref scope Ok!T ok) => pred(ok.get),
			(in Err!E) => other,
		);
	}
}

///
version(vtypechoice_unittest)
@safe pure nothrow @nogc unittest
{
	// source: https://doc.rust-lang.org/std/result/enum.Result.html#method.map_or
	auto x = Result!string.ok("foo");
	assert(x.fmapOr!(str => str.length)(42) == 3);

	auto y = Result!string.err("bar");
	assert(y.fmapOr!(str => str.length)(42) == 42);
}


template fmapOrElse(alias pred, alias orElse)
{
	auto fmapOrElse(T, E)(auto ref scope Result!(T, E) result)
		if (is(typeof(orElse(E.init)) : typeof(pred(T.init))))
	{
		// see: fmapOr
		return result.match!(
			(ref scope Ok!T ok) => pred(ok.get),
			(ref scope Err!E err) => orElse(err.get),
		);
	}
}

///
version(vtypechoice_unittest)
@safe pure nothrow @nogc unittest
{
	// source: https://doc.rust-lang.org/std/result/enum.Result.html#method.map_or_else
	auto k = 21;

	auto x = Result!string.ok("foo");
	assert(x.fmapOrElse!(str => str.length, e => k * 2) == 3);

	auto y = Result!string.err("bar");
	assert(y.fmapOrElse!(str => str.length, e => k * 2) == 42);
}


auto ref handle(alias pred, T, E)(return auto ref scope Result!(T, E) result)
{
	result.match!(
		(ref scope Err!E) {},
		(ref scope T ok) { cast(void) pred(ok); },
	);

	return result;
}

///
version(vtypechoice_unittest)
@safe pure nothrow @nogc unittest
{
	assert(Result!int.ok(3).handle!((ref n) => n += 7) == 10.ok);
	assert(Result!int.ok(3).handle!((ref n) => n + 7) == 3.ok);
	assert(Result!int.err("failure").handle!((ref n) => n = 0) == "failure".err);
}


auto ref handleErr(alias pred, T, E)(return auto ref scope Result!(T, E) result)
{
	// no forward because result is used below
	// therefore the received result must be passed by ref
	result.match!(
		(in Ok!T) {},
		(ref scope E err) { cast(void) pred(err); },
	);

	return result;
}

version(vtypechoice_unittest)
@safe pure nothrow @nogc unittest
{
	assert(Result!int.err("").handleErr!((ref n) => n = "failure") == "failure".err);
	assert(Result!int.err("failure").handleErr!(n => n = "") == "failure".err);
	assert(Result!int.ok(3).handleErr!((ref n) => n = "failure") == 3.ok);
}


bool has(T, E)(auto ref scope Result!(T, E) result, in T value)
{
	return result.match!(
		(in Err!E) => false,
		(in T ok) => ok == value,
	);
}

version(vtypechoice_unittest)
@safe pure nothrow @nogc unittest
{
	assert(Result!int.ok(3).has(3));
	assert(!Result!int.ok(3).has(0));
	assert(!Result!int.err("failure").has(3));
}


bool hasErr(T, E)(auto ref scope Result!(T, E) result, in E value)
{
	return result.match!(
		(in Ok!T) => false,
		(in E err) => err == value,
	);
}

version(vtypechoice_unittest)
@safe pure nothrow @nogc unittest
{
	assert(Result!int.err("failure").hasErr("failure"));
	assert(!Result!int.err("failure").hasErr("errors"));
	assert(!Result!int.ok(3).hasErr("failure"));
}


ref or(T, E)(return auto ref scope Result!(T, E) result, return auto ref scope Result!(T, E) other)
{
	return result.isOk() ? result : other;
}

///
version(vtypechoice_unittest)
// @safe but @trusted due to assign
@trusted pure nothrow @nogc unittest
{
	auto a = Result!int.ok(3);
	auto b = Result!int.err("failure");
	assert(a.or(b) is a);
	assert(b.or(a) is a);

	a = Result!int.err("failure");
	b = Result!int.err("late failure");
	assert(a.or(b) is b);

	a = Result!int.ok(3);
	b = Result!int.ok(10);
	assert(a.or(b) is a);
}


auto ref orElse(alias pred, T, E)(return auto ref scope Result!(T, E) result)
	if (is(typeof(pred(E.init)) == Result!(T, E)))
{
	return result.match!(
		(in Ok!T) => result,
		(E err) => pred(err),
	);
}

///
version(vtypechoice_unittest)
@safe pure nothrow @nogc unittest
{
	// source: https://doc.rust-lang.org/std/result/enum.Result.html#method.or_else
	alias R = Result!(int, int);

	auto sqr = delegate R(int x) => (x * x).ok;
	auto keep = delegate R(int x) => x.err;

	assert(R.ok(2).orElse!sqr.orElse!sqr == 2.ok);
	assert(R.ok(2).orElse!keep.orElse!sqr == 2.ok);
	assert(R.err(3).orElse!sqr.orElse!keep == 9.ok);
	assert(R.err(3).orElse!keep.orElse!keep == 3.err);
}


auto ref inout(T) unwrap(T, E)(auto ref scope inout Result!(T, E) result)
{
	return result.match!(
		function ref inout(T) (in inout Err!E) => assert(0),
		function ref inout(T) (return ref inout(T) value) => value,
	);
}

version(vtypechoice_unittest)
@safe pure nothrow @nogc unittest
{
	assert(Result!int.ok(3).unwrap() == 3);

	static assert(!__traits(compiles, &Result!int.ok(0).unwrap())); // not an lvalue
	immutable res = Result!int.ok(0);
	cast(void)&res.unwrap();
	static assert(__traits(compiles, &res.unwrap())); // ok lvalue

	static assert(is(typeof(res.unwrap()) == immutable int));
}


auto ref inout(E) unwrapErr(T, E)(return auto ref scope inout Result!(T, E) result)
{

	return result.match!(
		function ref inout(E) (in inout Ok!T) => assert(0),
		function ref inout(E) (return ref inout(E) value) => value,
	);
}

version(vtypechoice_unittest)
@safe pure nothrow @nogc unittest
{
	assert(Result!int.err("failure").unwrapErr() == "failure");

	immutable res = Result!int.err("");
	static assert(__traits(compiles, res.unwrapErr()));

	static assert(is(typeof(res.unwrapErr()) == immutable string));
}


version(vtypechoice_unittest)
@safe pure nothrow @nogc unittest
{
	with(Result!(immutable int))
	{
		static assert(!__traits(compiles, &ok(3).unwrap())); // not an lvalue
		immutable res = ok(3);
		static assert(__traits(compiles, &res.unwrap())); // ok lvalue

		static assert(is(typeof(ok(3).unwrap()) == immutable int));
		static assert(is(typeof(err("").unwrapErr()) == string));
		static assert(is(typeof(res.unwrapErr()) == immutable string));
	}
}


  // =====================
 // # Result as a range #
// =====================

version(vtypechoice_unittest)
@safe pure nothrow @nogc unittest
{
	static assert(__traits(compiles, () => Result!int.init[0]));

	auto r = Result!int.ok(3);

	assert(r[0] == 3);
	assert(r[0 .. $] is r);


	import std.algorithm.comparison : equal;
	import std.range : only;

	assert(r.equal(3.only));
	assert(r[0 .. $].equal(3.only));
	assert(r.length == 1);


	import std.algorithm.iteration : map, joiner;

	assert(Result!int.err("").map!(n => n + 1).empty);
	assert(r.only.joiner.front == 3);
}
