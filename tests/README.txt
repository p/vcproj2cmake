The unit tests contained in this directory
should be executed sufficiently frequently
in order to be able to catch regressions
in a timely manner.

It is also recommended to do a diff (diff -uN)
of result files produced by the converter,
of current vs. certain older versions,
to also detect differences in generated output
due to regressions.

When adding/extending features to the converter,
remember to add corresponding test content
to the tests' sample input files.

It obviously also is a good idea
to verify whether project files
can still be properly loaded without warnings/errors
in their original native IDEs.
