#!/usr/bin/env python
import sys
import os
import re
import subprocess
from enum import Enum

class GitPushAction(Enum):
    BRANCH_NEW = 1
    BRANCH_UPDATE = 2
    BRANCH_REMOVE = 3

class GitLabProtector:
    """GitLab Protector: A git pre-receive hook"""

    NULL_HASH = '0000000000000000000000000000000000000000'
    EMPTY_TREE_HASH = '4b825dc642cb6eb9a060e54bf8d69288fbee4904'

    groups = {}
    rules = []
    git_modified_files = []

    old_hash = None
    new_hash = None
    ref_name = None

    git_push_action = None

    def __get_repo_hash(self):
        path_symlink = sys.argv[0]
        file_this = os.path.basename(path_symlink)

        re_pattern = '^/.+/@hashed/([0-9a-fA-F]{2}/[0-9a-fA-F]{2}/[0-9a-fA-F]{64})\.git/custom_hooks/pre-receive.d/%s$' % file_this
        re_result = re.search(re_pattern, path_symlink)
        if re_result is None:
            print "GL-HOOK-ERR: Could not determine GitLab repository hash."
            exit(1)

        repo_hash_slashes = re_result.group(1)
        repo_hash = repo_hash_slashes.replace('/', '-')
        return repo_hash

    def __get_user_config_dir(self):
        path_symlink = sys.argv[0]
        path_target_of_symlink = os.path.realpath(path_symlink)
        dir_target_of_symlink = os.path.dirname(path_target_of_symlink)
        dir_base = os.path.join(dir_target_of_symlink, '..')
        dir_user_config = os.path.join(dir_base, 'user-config')
        return dir_user_config

    def __remove_comments_in_buf(self, buf_in):
        buf_out = []
        if buf_in:
            for line in buf_in:
                if(line.strip() == ''): continue
                if(re.match(r'^\s*#', line)): continue
                buf_out.append(line)
        return buf_out
 
    def load_protector_groups_config(self):
        self.groups = {}

        dir_user_config = self.__get_user_config_dir()
        file_groups_config = os.path.join(dir_user_config, 'groups.global.conf')
        try:
            with open(file_groups_config, 'r') as f:
                raw_groups_config = f.read()
                if raw_groups_config:
                    buf_with_comments = raw_groups_config.splitlines()
                    buf_groups_config = self.__remove_comments_in_buf(buf_with_comments)
        except:
            print "GL-HOOK-ERR: Could not read groups config: {0}".format(file_groups_config)
            exit(1)

        for line in buf_groups_config:
            tmp = line.split('=', 1)
            if len(tmp) != 2: continue

            group_name = tmp[0].strip()
            if group_name == '': continue

            users = tmp[1].strip()
            if users == '': continue

            users = users.split(',')

            ## Remove empty 'user' items
            for user in users:
                if user.strip() == '':
                    users.remove(user)

            self.groups[group_name] = users

        #print('groups == {0}'.format(self.groups))

    def load_protector_repo_config(self):
        rules = []

        repo_hash = self.__get_repo_hash()
        dir_user_config = self.__get_user_config_dir()
        file_repo_config = os.path.join(dir_user_config, 'repo.{0}.conf'.format(repo_hash))
        try:
            with open(file_repo_config, 'r') as f:
                raw_repo_config = f.read()
                if raw_repo_config:
                    buf_with_comments = raw_repo_config.splitlines()
                    buf_repo_config = self.__remove_comments_in_buf(buf_with_comments)
        except:
            print "GL-HOOK-ERR: Could not read user config: {0}".format(file_repo_config)
            exit(1)

        for line in buf_repo_config:
            tmp = line.split('=', 1)
            if len(tmp) != 2: continue

            group_name = tmp[0].strip()
            if group_name == '': continue

            pattern = tmp[1].strip()
            if pattern == '': continue

            self.rules.append({'pattern': pattern, 'group': group_name})

        #print('rules == {0}'.format(self.rules))

    def load_git_modified_files(self):
        self.git_modified_files = []

        ## Incoming format on STDIN: "old_hash new_hash ref_name"
        raw_stdin = sys.stdin.read()
        (old_hash, new_hash, ref_name) = raw_stdin.strip().split()
        #print "old_hash<{0}> new_hash<{1}> ref_name<{2}>".format(old_hash, new_hash, ref_name)

        self.old_hash = old_hash
        self.new_hash = new_hash
        self.ref_name = ref_name

        if new_hash == self.NULL_HASH:
            ## Don't validate branches to be removed
            self.git_push_action = GitPushAction.BRANCH_REMOVE
            return

        if old_hash == self.NULL_HASH:
            ## New branch is being pushed
            self.git_push_action = GitPushAction.BRANCH_NEW
            old_hash = self.EMPTY_TREE_HASH
            proc = subprocess.Popen(['git', 'diff','--name-only', old_hash, new_hash], stdout=subprocess.PIPE)
        else:
            ## Branch is being updated
            self.git_push_action = GitPushAction.BRANCH_UPDATE
            proc = subprocess.Popen(['git', 'diff','--name-only', old_hash, new_hash], stdout=subprocess.PIPE)

        raw_stdout = proc.stdout.readlines()

        if raw_stdout:
            for line in raw_stdout:
                filename = str(line.strip('\n'))
                self.git_modified_files.append(filename)

        #print('git_modified_files == {0}'.format(self.git_modified_files))
                
    def __is_user_name_in_group(self, user_name, group_name):
        if group_name:
            if group_name in self.groups:
                for user in self.groups[group_name]:
                    if user == user_name: return True
        return False

    def validate(self):
        is_success = True

        if(self.git_push_action is GitPushAction.BRANCH_NEW
        or self.git_push_action is GitPushAction.BRANCH_UPDATE):
            if not self.validate_file_permissions(): is_success = False
            #if not self.validate_file_sizes(): is_success = False

        return is_success

    def validate_file_sizes(self):
        print u"\033[0;37;1m\u2022 Validation Phase: File Sizes\033[0m".encode('utf8')
        validation_successful = True

        ## TODO Finish implementation of this feature.
        ## TODO Getting the file sizes does already work.
        ## TODO Make max file size configurable per repo in user config.
        DUMMY_5MB_LIMIT = 1024 * 1024 * 5
        max_filesize = DUMMY_5MB_LIMIT ## TODO just for testing! read from config file

        errors = []
        for git_modified_file in self.git_modified_files:
            proc = subprocess.Popen(['git', 'cat-file', '-s', '{0}:{1}'.format(self.new_hash, git_modified_file)], stdout=subprocess.PIPE)
            raw_stdout = proc.stdout.readlines()
            if raw_stdout:
                for line in raw_stdout:
                    filesize = int(line.strip('\n'))
                    if filesize is None:
                        filesize = 0
                    if(filesize > max_filesize):
                        validation_successful = False
                        errors.append({ 'filename': git_modified_file, 'filesize': filesize})

        if validation_successful:
            return True
        else:
            print "GL-HOOK-ERR: [POLICY] The following files exceed the maximum filesize limit of {0} byte(s):".format(max_filesize)
            for error in errors:
                print u'GL-HOOK-ERR: Filesize limit check: \u274C {0} - Filesize: {1} byte(s)'.format(error['filename'], error['filesize']).encode('utf8')
            return False

    def validate_file_permissions(self):
        print u"\033[0;37;1m\u2022 Validation Phase: File Permissions\033[0m".encode('utf8')
        validation_successful = True

        gitlab_user_id = os.environ.get('GL_ID')
        gitlab_user_name = os.environ.get('GL_USERNAME')
        gitlab_project_id = os.environ.get('GL_REPOSITORY')
        #print "gitlab_user_id<{0}> gitlab_user_name<{1}> gitlab_project_id<{2}>".format(gitlab_user_id, gitlab_user_name, gitlab_project_id)

        errors = []
        for git_modified_file in self.git_modified_files:
            rule_index = -1
            for rule in self.rules:
                rule_index = rule_index + 1
                match = re.search(rule['pattern'], git_modified_file)
                if match is None: continue

                ## A protected and modified file was detected which requires that the user
                ## who is pushing this change has to be a member of that configured group.
                if self.__is_user_name_in_group(gitlab_user_name, rule['group']):
                    print u'Protected file permission check: \u2714 {0}'.format(git_modified_file).encode('utf8')
                    continue
                else:
                    validation_successful = False
                    errors.append({ 'filename': git_modified_file, 'rule-index': rule_index})

        if validation_successful:
            return True
        else:
            print "GL-HOOK-ERR: [POLICY] You don't have permission to push changes for the following files:"
            for error in errors:
                print u'GL-HOOK-ERR: Protected file permission check: \u274C {0} - Rule Index: {1}'.format(error['filename'], error['rule-index']).encode('utf8')
            return False

    def __init__(self):
        print "\033[0;37;4mGitLab Protector\033[0m: Started"
        
        self.load_protector_groups_config()
        self.load_protector_repo_config()
        self.load_git_modified_files()

        is_success = self.validate()

        result_string = '\033[42;30;1m SUCCESSFUL \033[0m' if is_success else '\033[41;37;1m FAILED \033[0m'
        print "\033[0;37;4mGitLab Protector\033[0m: Validation {0}".format(result_string)

        exit(0) if is_success else exit(1)

GitLabProtector()

