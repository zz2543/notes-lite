---
name: mp-4-implement
description: "【中文】【主流程 第4步·逐张】根据规格或一组工单实现一项工作（在约定的接缝处驱动 tdd，完成后用 code-review 收尾）。  ‖ Original: Implement a piece of work based on a spec or set of tickets."
disable-model-invocation: true
---

Implement the work described by the user in the spec or tickets.

If the user passes a ticket reference, fetch it from the issue tracker and state its title before starting. If the reference is ambiguous, ask.

Call the Skill tool with "tdd" where possible, at pre-agreed seams.

Run typechecking regularly, single test files regularly, and the full test suite once at the end.

Once done, call the Skill tool with "code-review" to review the work.

Commit your work to the current branch.
