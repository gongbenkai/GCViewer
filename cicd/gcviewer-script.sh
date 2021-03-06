#!/bin/bash
# -e: exit on any non-true return value
# -u: exit, if an unset variable is being used
# https://ss64.com/bash/set.html
set -eu

echo "TRAVIS_PULL_REQUEST = ${TRAVIS_PULL_REQUEST}"
echo "TRAVIS_BRANCH = ${TRAVIS_BRANCH}"
echo "TRAVIS_JDK_VERSION = ${TRAVIS_JDK_VERSION}"

#####################
# functions
#####################
function perform_snapshot_release() {
  echo "----------------"
  echo build and deploy to sourceforge \(SNAPSHOT only\)
  echo "----------------"
  mvn clean deploy javadoc:javadoc -P sourceforge-release --settings ./cicd/settings.xml
}

function init_github() {
  git config --global user.email "travis@travis-ci.org"
  git config --global user.name "Travis CI"
  git remote add origin-github https://${GH_TOKEN}@github.com/chewiebug/gcviewer.git > /dev/null 2>&1
}

function push_to_github() {
  # https://gist.github.com/willprice/e07efd73fb7f13f917ea
  echo "pushing $1 to github"
  git status
  git push --quiet --set-upstream origin-github $1
}

function merge_with_develop_branch() {
  # assumption: we are not on the develop branch and should merge TRAVIS_BRANCH into develop
  echo "merging ${TRAVIS_BRANCH} into develop"
  # since travis did a shallow clone (git clone --depth=50 ...), we need to fetch the develop branch first
  git config remote.origin.fetch "+refs/heads/*:refs/remotes/origin/*"
  git fetch --depth=10
  git checkout develop
  git merge ${TRAVIS_BRANCH}
}

function perform_release() {
  echo "----------------"
  echo perform release
  echo "----------------"
  # maven release needs a locally checked out branch, otherwise "git symbolic-ref HEAD" will fail
  git checkout ${TRAVIS_BRANCH}
  openssl version
  openssl enc -d -aes-256-cbc -md sha1 -pass pass:$ENCRYPTION_PASSWORD -in $GPG_DIR/pubring.gpg.enc -out $GPG_DIR/pubring.gpg
  openssl enc -d -aes-256-cbc -md sha1 -pass pass:$ENCRYPTION_PASSWORD -in $GPG_DIR/secring.gpg.enc -out $GPG_DIR/secring.gpg
  mvn --batch-mode release:clean release:prepare release:perform --settings ./cicd/settings.xml
  # remove decrypted keyrings
  rm $GPG_DIR/*.gpg
  init_github
  push_to_github ${TRAVIS_BRANCH}
  # push tag, which was just generated by maven-release-plugin
  git push origin-github $(git describe --tags --abbrev=0)
  merge_with_develop_branch
  push_to_github develop
}

function perform_verify() {
  echo "----------------"
  echo only verify
  echo "----------------"
  mvn clean verify javadoc:javadoc
}

#####################
# script
#####################
# Since the same script is run several times with different jdks by the build process,
#   only under certain conditions, a (snapshot) release should be built.
#   Among others, a build loop must be prevented after a "perform_release" build was executed.
#   All other cases (like pull requests) only perform a "verify"
if [ "${TRAVIS_PULL_REQUEST}" = "false" ] && [[ ! "${TRAVIS_COMMIT_MESSAGE}" = \[maven-release-plugin\]* ]] && [ "${TRAVIS_JDK_VERSION}" = "openjdk8" ]
then
  if [ "${TRAVIS_BRANCH}" = "develop" ]
  then
    perform_snapshot_release
  elif [[ "${TRAVIS_BRANCH}" = "master" ]]
  then
    perform_release
  else
    # will be done for all other branches pushed into this repository
    perform_verify
  fi
else
  perform_verify
fi
