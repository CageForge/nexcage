# Contributing to Proxmox-LXCri

Thank you for your interest in contributing to Proxmox-LXCri! This document provides information on how you can help the project.

## How to Contribute

### Reporting Issues

If you find a bug or have a suggestion for improvement, please create an issue on GitHub. When creating an issue, please:

1. Use a clear and descriptive title
2. Provide a detailed description of the problem or suggestion
3. Include steps to reproduce the issue (if applicable)
4. Specify the expected behavior
5. Add appropriate labels

### Making Changes

1. Fork the repository
2. Create a new branch for your changes
3. Make your changes
4. Write tests for your changes
5. Ensure all tests pass
6. Submit a pull request

### Code Review

All pull requests must go through code review before merging. Please:

1. Ensure your code follows the project's style
2. Respond to reviewer comments
3. Make necessary changes based on feedback

### Documentation

Documentation improvements are also welcome! If you notice inaccuracies or have suggestions for improving the documentation, please:

1. Create an issue describing the problem
2. Submit a pull request with the proposed changes

## Code Standards

- Follow the project's code style
- Write tests for new code
- Update documentation as needed
- Ensure your code passes all tests

## Developer Certificate of Origin (DCO)

This project requires all contributions to be signed off with the Developer Certificate of Origin (DCO). This is a lightweight way for contributors to certify that they wrote or have the right to submit the code they are contributing.

### How to Sign Off

When making commits, you must sign off each commit:

```bash
git commit --signoff -m "Your commit message"
```

Or amend existing commits:
```bash
git commit --amend --signoff
```

For multiple commits in a PR:
```bash
git rebase --signoff HEAD~<number-of-commits>
```

### DCO Check

All pull requests are automatically checked for DCO signoff. If your PR fails the DCO check:

1. Add signoff to your commits:
   ```bash
   git commit --amend --signoff
   git push --force-with-lease
   ```

2. The DCO check will automatically re-run and pass once all commits are signed off.

### DCO Text

By signing off, you certify that your contribution is in accordance with the Developer Certificate of Origin (version 1.1):

```
Developer Certificate of Origin
Version 1.1

Copyright (C) 2004, 2006 The Linux Foundation and its contributors.

Everyone is permitted to copy and distribute verbatim copies of this
license document, but changing it is not allowed.

Developer's Certificate of Origin 1.1

By making a contribution to this project, I certify that:

(a) The contribution was created in whole or in part by me and I
    have the right to submit it under the open source license
    indicated in the file; or

(b) The contribution is based upon previous work that, to the best
    of my knowledge, is covered under an appropriate open source
    license and I have the right under that license to submit that
    work with modifications, whether created in whole or in part
    by me, under the same open source license (unless I am
    permitted to submit under a different license), as indicated
    in the file; or

(c) The contribution was provided directly to me by some other
    person who certified (a), (b) or (c) and I have not modified
    it.

(d) I understand and agree that this project and the contribution
    are public and that a record of the contribution (including all
    personal information I submit with it, including my sign-off) is
    maintained indefinitely and may be redistributed consistent with
    this project or the open source license(s) involved.
```

## License

By contributing, you agree that your contributions will be licensed under the Apache License 2.0.

## Contact

If you have questions about contributing, please contact us through:

- GitHub Issues
- moriarti@cp.if.ua
- [INSERT CHAT CHANNEL] 