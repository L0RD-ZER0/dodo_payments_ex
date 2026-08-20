%{
  configs: [
    %{
      name: "default",
      files: %{included: ["lib/", "test/"], excluded: ["deps/", "_build/"]},
      strict: true,
      checks: %{
        disabled: [
          {Credo.Check.Consistency.ExceptionNames, []},
          {Credo.Check.Design.AliasUsage, []},
          {Credo.Check.Readability.PreferImplicitTry, []},
          {Credo.Check.Readability.Specs, []},
          {Credo.Check.Refactor.Nesting, []}
        ]
      }
    }
  ]
}
