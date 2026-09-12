# Windows C# code style

Consistent formatting lets readers focus on behavior. Tools handle the mechanical rules; reviews cover choices that need context, including names, responsibilities, and failure handling.

The repository follows Microsoft's [C# identifier naming rules](https://learn.microsoft.com/en-us/dotnet/csharp/fundamentals/coding-style/identifier-names) and [common C# coding conventions](https://learn.microsoft.com/en-us/dotnet/csharp/fundamentals/coding-style/coding-conventions) where they fit its code and tools. Conventions tied to a particular game engine or unrelated framework do not apply here.

## Trust the repository tools

`windows/.editorconfig` defines C# and XAML formatting. Its settings take precedence over personal IDE preferences.

- C# and XAML use UTF-8, CRLF line endings, and four spaces for indentation.
- Use file-scoped namespaces and Allman braces.
- Place `using` directives outside namespaces and sort `System` entries first.
- Prefix interfaces with `I`, instance fields with `_`, and static fields with `s_`.
- Match namespaces to the folder structure.
- Treat `CA2012` and `CA2025` violations as build errors.

Use the following commands instead of checking formatting by eye:

```powershell
dotnet restore windows/SIDEY.Windows.slnx
dotnet format windows/SIDEY.Windows.slnx --verify-no-changes --no-restore
dotnet build windows/SIDEY.Windows.slnx --configuration Release --no-restore
dotnet test windows/SIDEY.Windows.slnx --configuration Release --no-restore --no-build
```

Automated checks cannot judge whether a name or structure is easy to understand. Use the following principles for those decisions.

## Make roles predictable from names

`RetryConnectionAsync()` tells a reader that the method retries a connection and completes asynchronously. `Handle()` forces the reader to open its implementation to learn both facts. A precise name keeps that context at the call site.

Use casing and prefixes as follows:

| Target | Rule | Example |
| --- | --- | --- |
| Namespace, type, method, property, event | `PascalCase` | `Sidey.Overlay.Rendering`, `ConnectionState` |
| Interface | `I` + `PascalCase` | `IHistoryCoordinator` |
| Local variable, parameter | `camelCase` | `retryCount`, `cancellationToken` |
| Instance field | `_camelCase` | `_connectionState` |
| Static field | `s_camelCase` | `s_defaultTimeout` |
| Thread-static field | `t_camelCase` | `t_currentContext` |
| Constant | `PascalCase` | `MaximumRoomCount` |
| Generic type parameter | `T` or `T` + role | `T`, `TMessage` |

Parameters of positional records become public properties, so use `PascalCase` for them. Use `camelCase` for ordinary constructor and method parameters.

```csharp
public sealed record MessageSnapshot(string Text, DateTimeOffset SentAt);

public sealed class MessageStore
{
    private readonly string _connectionString;

    public MessageStore(string connectionString)
    {
        _connectionString = connectionString;
    }
}
```

Put only information that identifies the role in a name.

- End an asynchronous method with `Async` when it actually returns asynchronous work.
- Expose important units or coordinate systems in names such as `timeoutMs`, `logicalPosition`, and `screenPixels`.
- End a type derived from `Attribute` with `Attribute`.
- Use singular names for ordinary enums and plural names for `[Flags]` enums that represent combinations.
- Express a Boolean name positively so that its `true` value is clear. Use `Is`, `Has`, or `Can` when natural, but do not require these prefixes mechanically.
- Name events for state changes that have already occurred. A method that raises an event may follow the .NET convention of a name such as `OnConnectionChanged()`, but do not prefix the event itself with `On`.
- Prefer a capability name over one that refers to the whole app. `IHistoryCoordinator`, for example, has a clearer scope than `IApplicationCoordinator`.

Spell out abbreviations that readers outside the team may not recognize. Keep established terms such as HTTP, DPI, and Win32 when the documentation already explains them. Reserve single-letter names for short loop indexes and formulas whose scope and meaning are immediately visible.

C# permits identifiers that prefix keywords with `@` or contain Unicode characters. Prefer a readable English name that avoids the keyword. Also avoid double underscores (`__`), which readers can mistake for compiler-reserved forms.

## Use `var` when the type is immediately apparent

Use `var` when the right-hand expression already names the type.

```csharp
var coordinator = new AppCoordinator(...);
```

Write the type when a return type is important to understanding the behavior or is difficult to infer from the expression.

```csharp
CoordinatorState state = await stateStore.LoadAsync(cancellationToken);
```

Keep type information close to the code that needs it. Use C# keywords such as `string`, `int`, and `bool` instead of `String`, `Int32`, and `Boolean`.

## Choose modern syntax when it clarifies the code

Use new syntax when it makes the code shorter and easier to read. Leave existing code alone when the change offers no other benefit.

- Prefer string interpolation to a chain of `+` operators when composing strings.
- Consider `StringBuilder` to reduce unnecessary allocations when building strings repeatedly in a loop.
- Consider a raw string literal when a string contains many quotation marks and line breaks.
- A collection expression may be used when the collection type is clear.
- Use a `using` declaration when the resource lifetime naturally matches the current scope.
- Use LINQ when it communicates the transformation more clearly. In frequently executed paths such as a render loop, decide only after measuring allocations and execution time.

`&&` and `||` may skip the right-hand expression based on the left-hand condition. When short-circuiting prevents null access or an expensive call, names and structure should make the evaluation order obvious.

## Show execution scope with braces and line breaks

Braces make execution scope visible and keep that scope intact when a later change adds another statement.

- Put an opening brace on a new line.
- Use braces for `if`, `else`, and loops, even when the body contains one line.
- Put one statement and one local-variable declaration on each line.
- Let `.editorconfig` determine spacing around operators and commas.
- Do not use spaces to align tokens vertically across lines. A name or type change would create unrelated edits.

A fixed line length is a poor reason to wrap code. Split an expression when the line carries too much information, using meaningful names or a simpler call structure.

## Keep code that changes together close together

Code is cohesive when responsibilities that change for the same reason stay together. A class that owns both connection retries and pixel rendering forces either change to account for the other's state and lifetime. Split responsibilities that change independently.

- Keep one independent primary type in each file.
- Structure a method to produce one result.
- Handle invalid input and exit conditions first with guard clauses.
- If a large parameter list makes call semantics difficult to remember, consider grouping related values into a type or separating responsibilities.
- Similar overloads make callers memorize their differences. Keep them together only when the options perform the same operation; otherwise, separate their names and responsibilities.
- Make state changes predictable from a method's name and return value. Do not hide side effects in a method that appears to be a query.
- Do not split a type or method at an arbitrary number of lines. Split it when its parts change for different reasons.

Comments should record reasons that the code cannot show. Win32 constraints, privacy boundaries, and performance tradeoffs all qualify. A note beside `count++` saying that it increments the count adds nothing.

Public APIs need XML comments when callers cannot infer usage conditions, exceptions, or ownership from names and types. Skip comments that only restate the signature.

## Do not hide exceptions

Catch the narrowest exception the current layer can handle. Let other exceptions reach a higher boundary, and use `throw;` when rethrowing to preserve the original call stack.

Use a broad `catch` only at boundaries where a failure must not escape the process, such as:

- process startup and shutdown;
- UI commands and native callbacks;
- the render loop; and
- failure within diagnostics itself.

At these boundaries, record diagnostics without personal data or turn the failure into a recovery action available to the user. Never discard it silently.

## Make ownership of asynchronous work and resources visible

Await I/O all the way through. Blocking with `.Result`, `.Wait()`, or `.GetAwaiter().GetResult()` can freeze the UI thread or cause a deadlock.

The object that starts a long-running operation keeps its task, cancels it, observes exceptions, and waits for it during shutdown. Code that creates a timer, socket, native handle, or cancellation token source must also show who disposes it.

Use `ValueTask` when synchronous completion is common and the contract allows exactly one await. Require evidence of that completion pattern before replacing `Task`.

## Keep GlobalUsings small

Global usings remove namespace imports repeated across a project. A namespace used by one feature belongs in that feature's files so their dependencies stay visible.

Before adding an entry, check:

1. Is it repeated across multiple files in the project?
2. Can a reader predict the type's source without name conflicts?
3. Does it avoid hiding a prohibited project dependency?

If any answer is no, use a local using in the relevant file.

## Do not put user-facing text in code

Store user-facing text as keys in `src/Sidey.App/Langs/*.json`, then retrieve it through `I18n.Get()` or `I18n.Format()`. Hard-coded Korean or English strings are easy to miss during translation and bypass the catalog parity tests.

Follow [`logging-en.md`](logging-en.md) for logging privacy rules, [`localization-en.md`](localization-en.md) for translation rules, and [`architecture-en.md`](architecture-en.md) for layer rules.
