module app;

version(vtypechoice_unittest)
version(D_BetterC)
extern(C) int main()
{
	import vtypechoice;
	import core.stdc.stdio : printf;

	alias units = imported!"std.meta".AliasSeq!(
		__traits(getUnitTests, vtypechoice.result),
		__traits(getUnitTests, vtypechoice.optional),
	);

	static foreach (test; units)
	{
		test();
	}

	printf("2 modules passed unittests\n");

	return 0;
}
