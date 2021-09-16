#!/bin/bash
set -e
set -o pipefail

if [[ -z "$GITHUB_TOKEN" ]]; then
	echo "Set the GITHUB_TOKEN env variable."
	exit 1
fi

if [[ -z "$GITHUB_REPOSITORY" ]]; then
	echo "Set the GITHUB_REPOSITORY env variable."
	exit 1
fi

URI=https://api.github.com
API_VERSION=v3
API_HEADER="Accept: application/vnd.github.${API_VERSION}+json; application/vnd.github.antiope-preview+json"
AUTH_HEADER="Authorization: token ${GITHUB_TOKEN}"

add_shortcut_label() {
	echo "Adding labels"
	LABELS=$(cat $GITHUB_EVENT_PATH | jq '.pull_request.labels[.pull_request.labels| length] |= . + { "name": "NEEDS SHORTCUT CARD" }' | jq '{ "labels": [ .pull_request.labels[].name ] }')
	curl --data "${LABELS}" -X PATCH -sSL -H "${AUTH_HEADER}" -H "${API_HEADER}" "${URI}/repos/${GITHUB_REPOSITORY}/issues/${NUMBER}"
}

remove_shortcut_labels(){
	echo "Removing labels"
	LABELS=$(cat $GITHUB_EVENT_PATH | jq '{ "labels": [ .pull_request.labels[].name ] }')
	LABELS=${LABELS[@]/'NEEDS SHORTCUT CARD'}
	# the below two lines removes orphaned quotes from the string. it's an ugly, temporary solution
	LABELS=${LABELS[@]/'"", '}
	LABELS=${LABELS[@]/', ""'}
	LABELS=${LABELS[@]/', ""'}
	LABELS=${LABELS[@]/' "" '}
	echo $LABELS
	curl --data "${LABELS}" -X PATCH -sSL -H "${AUTH_HEADER}" -H "${API_HEADER}" "${URI}/repos/${GITHUB_REPOSITORY}/issues/${NUMBER}"
}

main() {
	printenv
	cat $GITHUB_EVENT_PATH

	# Get the pull request number.
	NUMBER=$(jq --raw-output .number "$GITHUB_EVENT_PATH")

	echo "running $GITHUB_ACTION for PR #${NUMBER}"

	body=$(curl -sSL -H "${AUTH_HEADER}" -H "${API_HEADER}" "${URI}/repos/${GITHUB_REPOSITORY}/pulls/${NUMBER}")
	PR_BODY=$(echo "$body" | jq --raw-output .body)
	PR_BASE=$(echo "$body" | jq --raw-output .base.ref)
	PR_HEAD=$(echo "$body" | jq --raw-output .head.ref)
	body=$(curl -sSL -H "${AUTH_HEADER}" -H "${API_HEADER}" "${URI}/repos/${GITHUB_REPOSITORY}/pulls/${NUMBER}/commits")
	PR_COMMIT_MESSAGES=$(echo "$body" | jq -r .[].commit.message)

	# don't check for a card if we are merging dev to master
	if [[ ${PR_BASE} == "master" && ${PR_HEAD} == "development" ]]
	then
		remove_shortcut_labels
		exit 0
	fi

	# check if the branch path has a shortcut card associated
	if [[ ${PR_COMMIT_MESSAGES} =~ (\[sc[-0-9](.+)\])([^,]*) ]]
	then
		echo "Commit messages contain a shortcut card. You may proceed...this time."
		remove_shortcut_labels
		exit 0
	elif [[ ${GITHUB_REF} =~ (\/sc[-0-9](.+)\/*)([^,]*) ]] || [[ ${PR_HEAD} =~ (\/sc[-0-9](.+)\/*)([^,]*) ]]
	then
		echo "This branch was clearly created using the shortcut helper."
		remove_shortcut_labels
		exit 0
	elif [[ ${PR_BODY} =~ (\[sc[-0-9](.+)\])([^,]*) ]]
  then
		echo "If I said your PR body looked good, would you hold it against me?"
		remove_shortcut_labels
		exit 0
	elif [[ ${PR_BODY} =~ \(https:\/\/app\.shortcut\.com\/shipt\/story\/[0-9]*\/.*\) ]]
	then
		echo "Thanks for using the admin PR template."
		remove_shortcut_labels
		exit 0
  else
  	echo "yo dawg, where da shortcut card at?"
		add_shortcut_label
    exit 1
  fi
}

main
