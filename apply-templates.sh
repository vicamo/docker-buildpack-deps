#!/usr/bin/env bash
set -Eeuo pipefail

[ -f versions.json ] # run "versions.sh" first

jqt='.jq-template.awk'
if [ -n "${BASHBREW_SCRIPTS:-}" ]; then
	jqt="$BASHBREW_SCRIPTS/jq-template.awk"
elif [ "$BASH_SOURCE" -nt "$jqt" ]; then
	wget -qO "$jqt" 'https://github.com/docker-library/bashbrew/raw/5f0c26381fb7cc78b2d217d58007800bdcfbcfa1/scripts/jq-template.awk'
fi

if [ "$#" -eq 0 ]; then
	versions="$(jq -r 'keys | map(@sh) | join(" ")' versions.json)"
	eval "set -- $versions"
fi

generated_warning() {
	cat <<-EOH
		#
		# NOTE: THIS DOCKERFILE IS GENERATED VIA "apply-templates.sh"
		#
		# PLEASE DO NOT EDIT IT DIRECTLY.
		#

	EOH
}

for version; do
	# amd64, arm64, etc
	arch="$(basename "$version")"
	# buster, bullseye, focal, etc
	codename="$(basename "$(dirname "$version")")"
	# debian, ubuntu
	dist="$(dirname "$(dirname "$version")")"
	export arch codename dist version

	variants="$(jq -r '.[env.version].variants | map(@sh) | join(" ")' versions.json)"
	eval "variants=( $variants )"

	for variant in "${variants[@]}"; do
		template="Dockerfile${variant:+-$variant}.template"
		target="$version${variant:+/$variant}/Dockerfile"

		{
			generated_warning
			if [ "$arch" = "amd64" ]; then
				echo "FROM buildpack-deps:${codename}${variant:+-$variant}"
			else
				gawk -f "$jqt" "$template"
			fi
		} > "$target"
	done
done
