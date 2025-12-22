# Contributing to NixActions

Thank you for your interest in contributing to NixActions! This document provides guidelines and information for contributors.

## Table of Contents

- [Code of Conduct](#code-of-conduct)
- [Getting Started](#getting-started)
- [Development Setup](#development-setup)
- [Making Changes](#making-changes)
- [Submitting Changes](#submitting-changes)
- [Architecture](#architecture)

## Code of Conduct

Please be respectful and constructive in all interactions with the community.

## Getting Started

1. **Fork the repository** on GitHub
2. **Clone your fork** locally:
   ```bash
   git clone https://github.com/yourusername/nixactions.git
   cd nixactions
   ```
3. **Set up the development environment**:
   ```bash
   nix develop
   ```

## Development Setup

### Prerequisites

- Nix with flakes enabled
- Basic understanding of Nix language
- Familiarity with CI/CD concepts

### Running Examples

Test your changes by running the examples:

```bash
# Run all examples
nix run .#example-simple
nix run .#example-parallel
nix run .#example-complete
nix run .#example-secrets
nix run .#example-python-ci
nix run .#example-nix-shell
nix run .#example-artifacts
```

### Building

Build specific examples or the entire project:

```bash
# Build an example
nix build .#example-simple

# Build all packages
nix flake check
```

## Making Changes

### Project Structure

```
nixactions/
├── lib/                    # Core library
│   ├── default.nix        # Main API export
│   ├── mk-executor.nix    # Executor constructor
│   ├── mk-workflow.nix    # Workflow compiler
│   ├── executors/         # Built-in executors
│   └── actions/           # Standard actions
├── examples/              # Working examples
├── DESIGN.md             # Architecture documentation
└── README.md             # User documentation
```

### Types of Contributions

#### 1. Bug Fixes

- Check existing issues or create a new one
- Include a failing test case if possible
- Fix the bug and verify all examples still work

#### 2. New Executors

To add a new executor (e.g., `podman`):

1. Create `lib/executors/podman.nix`:
   ```nix
   { pkgs, mkExecutor }:
   
   mkExecutor {
     name = "podman";
     
     setupWorkspace = ''
       # Setup code
     '';
     
     cleanupWorkspace = ''
       # Cleanup code
     '';
     
     executeJob = { jobName, script }: ''
       # Execute job in podman container
       ${script}
     '';
   }
   ```

2. Export it in `lib/executors/default.nix`:
   ```nix
   {
     # ...
     podman = import ./podman.nix args;
   }
   ```

3. Add an example in `examples/podman-ci.nix`

4. Update documentation in README.md

#### 3. New Actions

To add a new action (e.g., `dockerBuild`):

1. Create `lib/actions/docker.nix`:
   ```nix
   { pkgs }:
   
   {
     build = { dockerfile ? "Dockerfile", tag }: {
       name = "docker-build";
       deps = [ pkgs.docker ];
       bash = ''
         docker build -f ${dockerfile} -t ${tag} .
       '';
     };
   }
   ```

2. Export it in `lib/actions/default.nix`

3. Add examples and documentation

#### 4. Documentation

- Keep README.md up to date with examples
- Update DESIGN.md for architectural changes
- Add inline comments for complex logic
- Update TODO.md roadmap if adding planned features

### Code Style

- **Nix**: Follow standard Nix formatting (use `nixpkgs-fmt`)
- **Bash**: Use proper quoting and error handling
- **Comments**: Write clear, concise comments
- **Naming**: Use descriptive names following existing conventions

### Testing

Before submitting:

1. **Run all examples**:
   ```bash
   for example in simple parallel complete secrets python-ci; do
     echo "Testing example-$example..."
     nix run .#example-$example
   done
   ```

2. **Check formatting**:
   ```bash
   nixpkgs-fmt --check .
   ```

3. **Verify builds**:
   ```bash
   nix flake check
   ```

## Submitting Changes

### Pull Request Process

1. **Create a feature branch**:
   ```bash
   git checkout -b feature/my-new-feature
   ```

2. **Make your changes** following the guidelines above

3. **Commit with clear messages**:
   ```bash
   git commit -m "Add podman executor with example"
   ```

4. **Push to your fork**:
   ```bash
   git push origin feature/my-new-feature
   ```

5. **Open a Pull Request** with:
   - Clear description of changes
   - Link to related issues
   - Examples of usage
   - Test results

### Pull Request Guidelines

- **Title**: Clear, descriptive summary
- **Description**: 
  - What changes were made
  - Why they were made
  - How to test them
- **Scope**: Keep PRs focused on a single feature/fix
- **Tests**: Include or update examples demonstrating the feature
- **Documentation**: Update relevant docs

### Review Process

1. Maintainers will review your PR
2. Address any feedback or requested changes
3. Once approved, your PR will be merged
4. Your contribution will be acknowledged in the release notes

## Architecture

Please read [DESIGN.md](./DESIGN.md) for detailed architecture documentation covering:

- Core concepts (Actions, Executors, Jobs, Workflows)
- Execution model (GitHub Actions-style parallelism)
- Secrets management
- Artifacts management
- Built-in executors and actions

## Questions?

- **Issues**: [GitHub Issues](https://github.com/yourusername/nixactions/issues)
- **Discussions**: [GitHub Discussions](https://github.com/yourusername/nixactions/discussions)

## Recognition

Contributors will be:
- Listed in release notes
- Acknowledged in the README
- Forever grateful for helping make CI/CD better!

Thank you for contributing to NixActions! 🎉
