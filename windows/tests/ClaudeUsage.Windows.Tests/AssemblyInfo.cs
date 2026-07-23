using Xunit;

// WPF's process-wide pack URI cache is not safe when multiple test classes
// construct XAML trees concurrently on separate STA threads. Serializing this
// UI test assembly prevents nondeterministic PackagePart stream corruption;
// the framework-independent Core tests remain parallelizable.
[assembly: CollectionBehavior(DisableTestParallelization = true)]
