module vtypechoice.optional;

import core.lifetime : forward;
import std.sumtype;

alias isOptional(T) = imported!"std.traits".isInstanceOf!(Optional, T);
alias isSome(T) = imported!"std.traits".isInstanceOf!(Some, T);
enum isNone(T) = is(imported!"std.traits".Unqual!T == None);

struct Optional(T)
{
	import core.lifetime : forward;
	import std.traits : CopyConstness, isInstanceOf, Unqual;
	import std.meta : AliasSeq, IndexOf = staticIndexOf, Map = staticMap;


	alias Some = .Some!T;
	alias None = .None;


	static some(U)(U s)
	{
		static if (.isSome!U)
		{
			static assert(.isOptional!T, "Cannot convert Some!("~U.stringof~") to "~Some.stringof);
			// lets perform: Optional!(Optional!int).some(Some!int(3));
			CopyConstness!(U, Optional) res = { st: Some(T.some(s.get)) };
		}
		else
			CopyConstness!(U, Optional) res = { st: (CopyConstness!(U, Some)(s)) };

		return res;
	}


	static some()(None)
	{
		static assert(.isOptional!T, "Cannot convert Some!(None) to "~Some.stringof);
		Optional res = { st: Some(T.none()) };

		return res;
	}


	static none()
	{
		Optional res = { st: .none() };

		return res;
	}


	bool opEquals(in Optional rhs) scope const
	{
		return st == rhs.st;
	}


	bool opEquals(in None _) scope const
	{
		return isNone();
	}


	bool opEquals(U)(in U rhs) scope const
		if (.isSome!U)
	{
		// allow comparing only with Some
		// turning opEquals into a template forces it to never cast to alias this
		// since Some alias to their template parameter type,
		// restricting the opEquals' parameter to Some would not evaluate
		// correctly if for example Some!(Some!T) was provided, as it would cast it
		// to Some!T making it the wrong comparison to perform
		enum errmsg = "Cannot compare "~U.stringof~" with "~Optional.stringof;

		// ensure this is a valid type comparison
		// fail here for a better error message, otherwise it'll fail with
		// a generic SumType's message
		static assert(__traits(compiles, T.init == rhs.get), errmsg);
		return st.match!(
			(in None _) => false,
			(in T ok) => ok == rhs.get,
		);
	}


	auto ref opAssign(U)(U rhs) scope return
		if (.isSome!U)
	{
		enum errmsg = "Cannot assign "~U.stringof~" to "~Optional.stringof;
		static if (.isSome!(typeof(U.get)))
			static assert (isSome!T, errmsg);

		static assert(__traits(compiles, () { T some; some = rhs.get; }), errmsg);

		st = rhs;

		return this;
	}


	auto ref opAssign(None) scope return
	{
		st = None();

		return this;
	}


	bool isNone() scope const
	{
		return st.match!((in value) => .isNone!(typeof(value)));
	}

	bool isSome() scope const
	{
		return !isNone();
	}


	  // ===================
	 // # Optional as range #
	// ===================

	alias back = front;
	alias empty = isNone;

	auto ref inout(T) front() scope return inout
	{
		return this.unwrap();
	}

	alias length = isSome;


	alias opDollar(size_t dim : 0) = length;

	ref opIndex() scope return
	{
		return this;
	}

	ref inout(T) opIndex(size_t index) scope return inout
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
	void popFront() scope { st = .none(); }


	inout(Optional) save() scope inout { return this; }


	SumType!(Some, None) st;
	alias st this;
}

///
version(vtypechoice_unittest)
@safe pure nothrow @nogc unittest
{
	alias O = Optional!int;

	assert(O.some(3) == Some!int(3));
	assert(O.none() == None());

	assert(O.some(3).match!(
		(None _) => false, // use Some/None to match
		(int) => true,   // or use the underlying type to match
	));

	assert(O.init == O.init);
	assert(O.some(0) != O.none());

	static assert(!__traits(compiles, O.init = Some!(Some!int).init));
	static assert(!__traits(compiles, Optional!O.init = Some!int.init));
	static assert(!__traits(compiles, O.init = Some!short.init)); // TODO: should this be allowed?

	static assert(!__traits(compiles, O.some(none)));
	static assert( __traits(compiles, Optional!O.some(none)));
	static assert( __traits(compiles, Optional!(Optional!O).some(none.some)));
	static assert( __traits(compiles, Optional!(Optional!O).some(10.some.some)));
	static assert(!__traits(compiles, Optional!(Optional!O).some(10.some.some.some)));
	static assert(!__traits(compiles, Optional!(Optional!O).some(10.some)));

	() @trusted
	{
		assert((O.some(3) = 10.some) == 10.some);
		assert((O.some(3) = none) == none);
	}
	();
}


struct Some(T)
{
	T get;
	alias get this;
}

auto some(T, string prettyFun = __PRETTY_FUNCTION__, string funName = __FUNCTION__)(T value)
{
	enum untilFunName = ()
	{
		for (size_t i; i + funName.length < prettyFun.length; i++)
			if (prettyFun[i .. i + funName.length] == funName)
				return i;

		return 0;
	} ();

	static if (is(mixin(prettyFun[0 .. untilFunName]) Type == Optional!U, U))
		return Type.some(value);
	else
		return Some!T(value);
}

///
version(vtypechoice_unittest)
@safe pure nothrow @nogc unittest
{
	static assert(__traits(compiles, () => 10.some));
	static assert(is(typeof(() { return 10.some; } ()) == Some!int));
	static assert(__traits(compiles, function Optional!int () => 10.some));
}



struct None {}

auto none(string prettyFun = __PRETTY_FUNCTION__, string funName = __FUNCTION__)()
{
	enum None n = {};

	enum untilFunName = ()
	{
		for (size_t i; i + funName.length < prettyFun.length; i++)
			if (prettyFun[i .. i + funName.length] == funName)
				return i;
		return 0;
	} ();

	static if (is(mixin(prettyFun[0 .. untilFunName]) Type == Optional!U, U))
		return Type.none();
	else
		return n;
}

///
version(vtypechoice_unittest)
@safe pure nothrow @nogc unittest
{
	static assert(__traits(compiles, () => none));
	static assert(is(typeof(() { return none; } ()) == None));

	static assert(__traits(compiles, function Optional!int () => none));
}


  // ====================================
 // # Optional's functional operations #
// ====================================

auto andThen(alias pred, T)(auto ref scope Optional!T optional)
	if (isOptional!(typeof(pred(T.init))))
{
	alias Type = imported!"std.traits".TemplateArgsOf!(typeof(pred(T.init)).Types[0]);

	return optional.match!(
		(in None _) => Optional!Type.none(),
		(ref scope T value) => pred(value),
	);
}

///
version(vtypechoice_unittest)
@safe pure nothrow @nogc unittest
{
	alias O = Optional!int;
	assert(O.none.andThen!(i => O.some(i + 3)) == none);
	assert(O.some(7).andThen!(i => O.some(i + 3)) == 10.some);
}


auto andThen(alias pred, T)(auto ref scope Optional!T optional)
	if (isSome!(typeof(pred(T.init))) || isNone!(typeof(pred(T.init))))
{
	static if (isSome!(typeof(pred(T.init))))
		alias Type = imported!"std.traits".TemplateArgsOf!(typeof(pred(T.init)))[0];
	else
		alias Type = T;

	return optional.match!(
		(in None _) => Optional!Type.none(),
		(ref scope T value) { Optional!Type opt = { st: (pred(value)) }; return opt; },
	);
}

///
version(vtypechoice_unittest)
@safe pure nothrow @nogc unittest
{
	alias O = Optional!int;
	assert(O.none.andThen!(i => some(i + 3)) == none);
	assert(O.some(7).andThen!(i => none) == none);
}


auto andThen(alias pred, T)(auto ref scope Optional!T optional)
	if (!isOptional!(typeof(pred(T.init)))
		&& !isSome!(typeof(pred(T.init)))
		&& !isNone!(typeof(pred(T.init))))
{
	alias Type = typeof(pred(T.init));

	return forward!optional.match!(
		(in None _) => Optional!Type.none(),
		(ref scope T value) => Optional!Type.some(pred(value)),
	);
}

///
version(vtypechoice_unittest)
@safe pure nothrow @nogc unittest
{
	alias O = Optional!int;
	assert(O.none.andThen!(i => i + 3) == none);
	assert(O.some(7).andThen!(i => i + 3) == 10.some);
}


Optional!T flatten(T)(auto ref scope Optional!(Optional!T) optional)
{
	return forward!optional.match!(
		(in None _) => Optional!T.none(),
		(in value) => value,
	);
}

///
version(vtypechoice_unittest)
@safe pure nothrow @nogc unittest
{
	alias O = Optional!(Optional!int);
	static assert(is(typeof(O.init.flatten()) == Optional!int));

	assert(O.some(3.some).flatten() == 3.some);
	assert(O.none.flatten() == none);
}


template fmap(alias pred)
{
	auto fmap(T)(auto ref scope Optional!T optional)
	{
		alias Type = typeof(pred(T.init));
		return optional.match!(
			(in None _) => Optional!Type.none(),
			(ref scope T value) => Optional!Type.some(pred(value)),
		);
	}
}

///
version(vtypechoice_unittest)
@safe pure nothrow @nogc unittest
{
	assert(Optional!int.some(3).fmap!(n => n + 7) == 10.some);

	import std.algorithm: equal, map;
	import std.range : only;
	assert(Optional!int.some(3).only.map!(fmap!(n => n + 7)).equal(10.some.only));
}


template fmapOr(alias pred)
{
	auto fmapOr(U, T)(auto ref scope Optional!T optional, auto ref scope U other)
	{
		// simmulate an implicit cast to pred's return type
		// if the return type is know to be ulong and an int is provided,
		// the program would compile and run if U was written as size_t
		// however, as it isn't, it would fail because !is(size_t : int)
		// by placing Ok!T first the return type will be pred's return type
		// forcing other to be implicitly castable to it
		return optional.match!(
			(ref scope Some!T value) => pred(value.get),
			(in None _) => other,
		);
	}
}

///
version(vtypechoice_unittest)
@safe pure nothrow @nogc unittest
{
	auto x = Optional!string.some("foo");
	assert(x.fmapOr!(str => str.length)(42) == 3);

	auto y = Optional!string.none();
	assert(y.fmapOr!(str => str.length)(42) == 42);
}


template fmapOrElse(alias pred, alias orElse)
{
	auto fmapOrElse(T)(auto ref scope Optional!T optional)
		if (is(typeof(orElse()) : typeof(pred(T.init))))
	{
		// see: fmapOr
		return optional.match!(
			(ref scope Some!T value) => pred(value.get),
			(in None _) => orElse(),
		);
	}
}

///
version(vtypechoice_unittest)
@safe pure nothrow @nogc unittest
{
	auto x = Optional!string.some("foo");
	assert(x.fmapOrElse!(str => str.length, () => 42) == 3);

	auto y = Optional!string.none();
	assert(y.fmapOrElse!(str => str.length, () => 42) == 42);
}


auto ref handle(alias pred, T)(return auto ref scope Optional!T optional)
{
	optional.match!(
		(in None _) {},
		(ref scope T value) { cast(void) pred(value); },
	);

	return optional;
}

///
version(vtypechoice_unittest)
@safe pure nothrow @nogc unittest
{
	assert(Optional!int.some(3).handle!((ref n) => n += 7) == 10.some);
	assert(Optional!int.some(3).handle!((ref n) => n + 7) == 3.some);
	assert(Optional!int.none.handle!((ref n) => n = 0) == .none);
}


bool has(T)(auto ref scope Optional!T optional, in T other)
{
	return optional.match!(
		(in None _) => false,
		(in T value) => value == other,
	);
}

version(vtypechoice_unittest)
@safe pure nothrow @nogc unittest
{
	assert(Optional!int.some(3).has(3));
	assert(!Optional!int.some(3).has(0));
	assert(!Optional!int.none.has(3));
}


ref or(T)(return auto ref scope Optional!T optional, return auto ref scope Optional!T other)
{
	return optional.isSome() ? optional : other;
}

///
version(vtypechoice_unittest)
// @safe but @trusted due to assign
@trusted pure nothrow @nogc unittest
{
	auto a = Optional!int.some(3);
	auto b = Optional!int.none();
	assert(a.or(b) is a);
	assert(b.or(a) is a);

	a = Optional!int.none();
	b = Optional!int.none();
	assert(a.or(b) is b);

	a = Optional!int.some(3);
	b = Optional!int.some(10);
	assert(a.or(b) is a);
}


auto ref orElse(alias pred, T)(return auto ref scope Optional!T optional)
	if (is(typeof(pred()) == Optional!T))
{
	return optional.match!(
		(in Some!T) => optional,
		(in None _) => pred(),
	);
}

///
version(vtypechoice_unittest)
@safe pure nothrow @nogc unittest
{
	// source: https://doc.rust-lang.org/std/option/enum.Option.html#method.or_else
	alias O = Optional!string;

	auto nobody = function O() => none;
	auto vikings = function O() => "vikings".some;

	assert(O.some("barbarians").orElse!vikings == "barbarians".some);
	assert(O.none.orElse!vikings == "vikings".some);
	assert(O.none.orElse!nobody == none);
}


auto ref inout(T) unwrap(T)(auto ref scope inout Optional!T optional)
{
	return optional.match!(
		function ref inout(T) (in inout None _) => assert(0),
		function ref inout(T) (return ref inout(T) value) => value,
	);
}

version(vtypechoice_unittest)
@safe pure nothrow @nogc unittest
{
	assert(Optional!int.some(3).unwrap() == 3);

	static assert(!__traits(compiles, &Optional!int.some(0).unwrap())); // not an lvalue
	immutable opt = Optional!int.some(0);
	static assert(__traits(compiles, &opt.unwrap())); // ok lvalue

	static assert(is(typeof(opt.unwrap()) == immutable int));
}



  // =====================
 // # Optional as a range #
// =====================

@safe pure nothrow @nogc unittest
{
	static assert(__traits(compiles, () => Optional!int.init[0]));

	auto r = Optional!int.some(3);

	assert(r[0] == 3);
	assert(r[0 .. $] is r);


	import std.algorithm.comparison : equal;
	import std.range : only;

	assert(r.equal(3.only));
	assert(r[0 .. $].equal(3.only));
	assert(r.length == 1);


	import std.algorithm.iteration : map, joiner;

	assert(Optional!int.none.map!(n => n + 1).empty);
	assert(r.only.joiner.front == 3);
}
