# Korean Developer-Guide Style

Read this reference only when drafting or revising a Korean guide under `windows/docs/**`.

## Use a consistent informal-polite register

Use the informal-polite Korean register consistently. Do not mix it with formal-polite or plain declarative endings. Explain rules alongside the reader rather than stacking terse commands.

Keep code identifiers, product names, API names, commands, and established platform terms unchanged. A contributor must be able to search for the exact term in code or official documentation.

## Explain terms where they first matter

Keep an exact technical term, briefly explain its meaning at first use, and connect it to a concrete consequence in the same paragraph. Replace abstract benefits such as “better maintainability” with an observable effect, such as which caller, state owner, or lifecycle a contributor no longer has to inspect.

Name the responsible component when ownership matters. Prefer an active sentence that identifies who creates, observes, cancels, restores, or disposes a resource. Do not force an active construction when it makes Korean less natural.

## Preserve readable rhythm

- Use paragraphs for connected reasoning and lists for actual sets, choices, or procedures.
- Vary sentence length naturally and avoid repeating transition words at the start of each paragraph.
- Move important exceptions out of crowded parentheses and into complete sentences.
- Avoid unnecessary English glosses, quotation marks, bold emphasis, and mechanically repeated bullet patterns.

On the final pass, confirm that the register is consistent, technical meaning and identifiers are unchanged, terms are explained near first use, and abstract claims have concrete consequences.
