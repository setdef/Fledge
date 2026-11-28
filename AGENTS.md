<!--
  SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
  SPDX-License-Identifier: CC-BY-SA-4.0
-->

# **ONLY HUMANS MAY EDIT THIS FILE!**

# AI Agent Instructions

You must read and be bound by @CONTRIBUTING.md, but this file outranks it.

## Running the tools

- Run the repository's tools as `MISE_TRUSTED_CONFIG_PATHS=$PWD mise exec -- <command>`.

## Weighing options

Judge each option for a decision against what it must serve: the requirements in the design documents, the drivers in the ADRs, and [the Tao](CONTRIBUTING.md#the-tao-of-fledge). Report which options you weighed and why each lost, and check each reason against the requirement it cites. Popularity counts for less than quality, what an option can do, and performance, such as speed and memory. When an option is popular, ask what its popularity stands for and what choosing it trades away.

## Agents that delegate

An AI agent that hands work to other agents passes these rules on to them, and answers for their work: for each judgment call they make, each change they make to a Markdown file in the repository, and each recommendation they propose. When any of these is wrong, the agent fixes the work or reverts it.

## Quality

- RubyCritic, RuboCop, Steep, test coverage, `reuse lint`, and the rest of the deterministic quality suite stay at their maximum. A floor stays or rises, and lowers only with the maintainer's permission, which he rarely gives.
- Numbers from such software are always clues about required quality, never targets to meet, scores to game, or goals to optimize for.
- This repo is existing software, and you must improve its design when the quality tooling reports a problem. It has accumulated technical debt, and Martin Fowler's Design Stamina Hypothesis states that it must be refactored. Take small, green steps. Think about design and modeling and writing, not evals or scores or code or points. When a quality gate denies your work, pause your work and start by writing into a scratch file everything you can remember about OOA&D, OOP, object design, domain modeling, analysis, and clear writing. Remember: _Clean Code_ by Robert C. Martin; _Implementation Patterns_ by Kent Beck; _Code Complete 2_ by Steve McConnell; _Refactoring: Improving the Design of Existing Code_ by Martin Fowler; _The Mikado Method_ by Ellnestam & Borland; _Refactoring to Patterns_ by Joshua Kerievsky; _Elegant Objects_ by Yegor Bugayenko; _Elements of Clojure_ by Zachary Tellman; _Smalltalk with Style_ by Skublics, Klimas, & Thomas; _Adaptive Code, Second Edition_ by Gary McLean Hall; _Applying UML and Patterns, Third Edition_ by Craig Larman; _Design Patterns: Elements of Reusable Object-Oriented Software_ by Gamma, Helm, Johnson, & Vlissides; _Core J2EE Patterns, Second Edition_ by Alur, Crupi, & Malks; _The Design Patterns Smalltalk Companion_ by Alpert, Brown, & Woolf; _Domain-Driven Design: Tackling Complexity in the Heart of Software_ by Eric Evans; _The Ruby Way, Third Edition_ by Hal Fulton; _Effective Ruby_ by Peter Jones; _Eloquent Ruby_ by Russ Olsen; _The Ruby Programming Language_ by David Flanagan & Yukihiro Matsumoto; _Object-Oriented Analysis & Design with Applications, Third Edition_ by Booch et al.; _Object Design_ by Rebecca Wirfs-Brock & Alan McKean; _Practical Object-Oriented Design in Ruby, Second Edition_ by Sandi Metz; _Smalltalk, Objects, and Design_ by Chamond Liu; _Object-Oriented Programming: An Evolutionary Approach_ by Brad J. Cox; _Touch of Class_ by Bertrand Meyer; _Object-Oriented Methods_ by Ian Graham; _99 Bottles of OOP_ by Sandi Metz; _Pattern-Oriented Software Architecture_ by Buschmann et al.; _Clean Architecture_ by Robert C. Martin; _Hexagonal Architecture Explained_ by Cockburn & Garrido de Paz; _Analysis Patterns_ by Martin Fowler; _Object-Oriented Systems Analysis: Modeling the World in Data_ by Shlaer & Mellor; and _Object Lifecycles: Modeling the World in States_ by Shlaer & Mellor.
