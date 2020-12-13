# GitLab Protector

A [git pre-receive hook](https://git-scm.com/book/en/v2/Customizing-Git-Git-Hooks) to add support for file protection with user/group management to your git repositories on self-hosted GitLab instances.

**GitLab Protector** will help protect your git repositories by only allowing modifications to certain files if permission has been given to the user who is trying to push new changes.

## Requirements

- Self-hosted GitLab instance (CE or EE)
- Probably `root` access to be able to install the hooks

## How it works

You will define **rules** per git repository and a (global) list of **groups** that is only known and used by **GitLab Protector**.

Each **rule** is a *Regular Expression* which specifies what files (and/or directories containing files) should be protected from modifications in a repository.
Files being protected means that from now on only a certain **group** of users are allowed to push commits to modify these files.

## Features

- Integration with GitLab CE and EE
- Git repository file protection with user and group management
- Comfortable management shell script
    - Install and uninstall hooks for specific repositories
    - Status display for each GitLab repository
        - GitLab repository name
        - GitLab hashed storage repository directory name
        - Using GitLab Protector?
        - Number of active rules
        - Error detection with auto-repair command

## Installation

```sh
$ cd /opt/

$ git clone git@github.com:andgeno/GitLab-Protector.git

$ cd GitLab-Protector

$ ./gitlab-protector.sh --help
```

You can move the `GitLab-Protector` directory to any location, e.g.: `/opt/GitLab-Protector/`.

Please make sure to not move this directory after installing your first **GitLab Protector** hook because this will break the symlink that was created in this process.
However, if you need to move its location later you can easily fix broken symlinks by running the command: `./gitlab-protector.sh fix` which will repair any broken hook symlinks.

## Usage

**GitLab Protector** can be fully administrated through the `gitlab-protector.sh` shell script.

Run the following command to display the help screen which explains all commands available:

```sh
$ ./gitlab-protector.sh --help
USAGE: gitlab-protector.sh [COMMAND] [OPTIONS...]

    COMMAND
        config, c [ARGS]       Start interactive configuration menu.
        fix, f                 Fix all dangling symlinks in repositories that use GitLab Protector.
        status, s              Display an overview of the configuration status per repository.
        uninstall, u           Start interactive uninstall menu for repositories.

    OPTIONS
        -h, --help             Show this help screen.

    ARGS for 'config'
        groups, g              Start interactive configuration menu for groups.
        repository, repo, r    Start interactive configuration menu for repositories.
```

A good start is to get an overview of your available GitLab repositories:

```sh
$ ./gitlab-protector.sh status
  GitLab hashed storage directory: /var/opt/gitlab/git-data/repositories/@hashed
  GitLab Protector user config   : /opt/GitLab-Protector/user-config

  GITLAB HASHED STORAGE REPOSITORY DIRECTORY                                 | INSTALLED | RULES | REPOSITORY NAME
  ---------------------------------------------------------------------------+-----------+-------+---------------------------------------
  ef/2d8527a891e224136950ff32ca212b45b/ef2d127de37b942babec78f5564afe39d.git |        no |       | android/app1
  4a/44/4a44dc15364204a80fe8e59718b9b5d03019c07d8b62b24f1e5233ade6af1dd5.git |        no |       | ios/app5
  b1/7e/b17ef6d19c7a5b16598d732768f7c726b4b621285ee83b907c5da0a9f4ce8cd9.git |       yes |     4 | test/project1
  94/00/9400f1b21b85303900aa912017db7617d8cb527d7fa3d3eafe5e4c5b4ca7f767.git |        no |       | test/project2
```

When you run the command `./gitlab-protector.sh status` for the first time you will probably see a warning that the groups configuration file is missing. Follow the instructions to create one.

After that, define your first rules by configuring a repository. Use the command `./gitlab-protector.sh config` or even faster `./gitlab-protector.sh config repository` to do that.
This will create a repository configuration file inside **GitLab Protector** for the GitLab repository you selected. You can verify this by running the command `./gitlab-protector.sh status` again.

## User configuration files

Your configuration files are located in `<GitLab-Protector>/user-config/`, e.g: `/opt/GitLab-Protector/user-config/`.

Note that your repository configuration files will still exist even after deleting a repository within GitLab.
You will have to remove your repository configuration files manually.

## Updating GitLab Protector

The update process is very easy. Simply run the following command while you are in the directory of **GitLab Protector**:

```sh
$ git pull
```

This will fetch and update your application files to the latest version.

In case something goes wrong you can always go back to a previous version - it's a git repository afterall! :-)

## Troubleshooting

If **GitLab Protector** is unable to find your GitLab repositories chances are that your server administrator has chosen a different location as GitLab's default.
In that case, take a quick look in the `gitlab-protector.sh` shell script file. At the top in the `CONFIG` section it describes how to set a custom location without
having to actually make changes to the shell script itself.

## Examples

The following examples show a demo configuration for groups and a demo repository.

There are three groups that have been configured in **GitLab Protector**.
To assign multiple users to the same group simply add them in a comma-separated list.

### Configuration file example for `groups.global.conf`
```ini
admin=andreas
artist=john,sally
developer=bob,tom,amanda,andreas
```

In this demo repository, four rules have been defined.

- Only users in the group `admin` are also allowed to modify `<repo root>/Jenkinsfile`.
- Users in the group `developer` are also allowed to modify all files in `<repo root>/source/` and `<repo root>/config`.
- Users in the group `artist` are also allowed to modify all files in `<repo root>/assets/`.

Please note, any other file paths that are not matching the specified rules remain modifiable for all users that have access to your git repository!

### Configuration file example for `repo.*.conf`
```ini
admin=^Jenkinsfile$
developer=^source/
developer=^config/
artist=^assets/
```

Now, take a look at the two examples below how GitLab would behave when users with different permissions try to modify and push their changes.

### Example 1

User `john` (without permission) trying to modify the existing and protected file `Jenkinsfile`

```sh
john@pc1 /home/john/dev/project1 (develop)
$ date > Jenkinsfile

john@pc1 /home/john/dev/project1 (develop)
$ git add Jenkinsfile

john@pc1 /home/john/dev/project1 (develop)
$ git commit -m "Testing GitLab Protector WITHOUT permission"
[develop 07d5f96] Testing GitLab Protector WITHOUT permission
 1 file changed, 1 insertion(+)

john@pc1 /home/john/dev/project1 (develop)
$ git push origin HEAD
Enumerating objects: 5, done.
Counting objects: 100% (5/5), done.
Delta compression using up to 32 threads
Compressing objects: 100% (2/2), done.
Writing objects: 100% (3/3), 327 bytes | 327.00 KiB/s, done.
Total 3 (delta 1), reused 0 (delta 0), pack-reused 0
remote: GitLab Protector: Started
remote: • Validation Phase: File Permissions
remote: GL-HOOK-ERR: [POLICY] You don't have permission to push changes for the following files:
remote: GL-HOOK-ERR: Protected file permission check: ❌ Jenkinsfile - Rule Index: 1
remote: GitLab Protector: Validation  FAILED
To https://gitlab.example.com/test/project1.git
 ! [remote rejected] HEAD -> develop (pre-receive hook declined)
error: failed to push some refs to 'https://gitlab.example.com/test/project1.git'
```

Note that the error message hints to the user which rule was used when a check has failed.
This should help to quickly track down potential configuration issues.

### Example 2

User `andreas` (with permission) trying to modify the existing and protected file `Jenkinsfile`

```sh
andreas@pc2 /home/andreas/dev/project1 (develop)
$ date > Jenkinsfile

andreas@pc2 /home/andreas/dev/project1 (develop)
$ git add Jenkinsfile

andreas@pc2 /home/andreas/dev/project1 (develop)
$ git commit -m "Testing GitLab Protector WITH permission"
[develop a61a763] Testing GitLab Protector WITH permission
 1 file changed, 1 insertion(+)

andreas@pc2 /home/andreas/dev/project1 (develop)
$ git push origin HEAD
Enumerating objects: 4, done.
Counting objects: 100% (4/4), done.
Delta compression using up to 32 threads
Compressing objects: 100% (2/2), done.
Writing objects: 100% (3/3), 287 bytes | 287.00 KiB/s, done.
Total 3 (delta 1), reused 0 (delta 0), pack-reused 0
remote: GitLab Protector: Started
remote: • Validation Phase: File Permissions
remote: Protected file permission check: ✔ Jenkinsfile
remote: GitLab Protector: Validation  SUCCESSFUL
remote:
remote: To create a merge request for develop, visit:
remote:   https://gitlab.example.com/test/project1/-/merge_requests/new?merge_request%5Bsource_branch%5D=develop
remote:
To https://gitlab.example.com/test/project1.git
   4241268..a61a763  develop -> develop
```


