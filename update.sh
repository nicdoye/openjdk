#!/usr/bin/env bash
set -Eeuo pipefail

cd "$(dirname "$(readlink -f "$BASH_SOURCE")")"

versions=( "$@" )
if [ ${#versions[@]} -eq 0 ]; then
	versions=( */ )
fi
versions=( "${versions[@]%/}" )

# sort version numbers with lowest first
IFS=$'\n'; versions=( $(echo "${versions[*]}" | sort -V) ); unset IFS

template-generated-warning() {
	local from="$1"; shift
	local javaVersion="$1"; shift

	cat <<-EOD
		#
		# NOTE: THIS DOCKERFILE IS GENERATED VIA "update.sh"
		#
		# PLEASE DO NOT EDIT IT DIRECTLY.
		#

		FROM $from

		LABEL name="Alfresco Base Java" \\
    vendor="Alfresco" \\
    license="Various" \\
    build-date="unset"
	EOD
}

travisEnv=
for javaVersion in "${versions[@]}"; do
	for javaVendor in oracle openjdk; do
		for javaType in jdk serverjre; do
			dir="$javaVersion/$javaVendor/$javaType"

			#if [ -n "$suite" ]; then
			if [ -d "${dir}" ]; then 

				template-generated-warning "centos:7.5.1804" "$javaVersion" > "$dir/Dockerfile"

				cat >> "$dir/Dockerfile" <<'EOD'

RUN yum -y update \
		yum-utils-1.1.31-46.el7_5 \
		yum-plugin-ovl-1.1.31-46.el7_5 \
		yum-plugin-fastestmirror-1.1.31-46.el7_5 \
		bind-license-9.9.4-61.el7_5.1 \
		python-2.7.5-69.el7_5 \
		gnupg2-2.0.22-5.el7_5 && \
		yum clean all
EOD

				cat >> "$dir/Dockerfile" <<-EOD

					# Set the locale
					ENV LANG en_US.UTF-8
					ENV LANGUAGE en_US:en
					ENV LC_ALL en_US.UTF-8
					ENV JAVA_HOME=/usr/java/default
		
				EOD

	# ENV JAVA_PKG=FIXME #"\$JAVA_PKG"

				cat >> "$dir/Dockerfile" <<EOD
# This used to be serverjre-*.tar.gz (and not an ARG)
# now it will be serverjre-8u181-bin.tar.gz / serverjre-11.0.0-bin.tar.gz
ENV JAVA_PKG="\$JAVA_PKG"
ADD \$JAVA_PKG /usr/java/

RUN export JAVA_DIR=\$(ls -1 -d /usr/java/*) && \\
		ln -s \$JAVA_DIR /usr/java/latest && \\
		ln -s \$JAVA_DIR /usr/java/default && \\
		alternatives --install /usr/bin/java java \$JAVA_DIR/bin/java 20000 && \\
		alternatives --install /usr/bin/javac javac \$JAVA_DIR/bin/javac 20000 && \\
		alternatives --install /usr/bin/jar jar \$JAVA_DIR/bin/jar 20000
EOD

				if [[ "$javaType" = 'jdk' ]] && [ "$javaVersion" -ge 10 ]; then
					cat >> "$dir/Dockerfile" <<-'EOD'

						# https://docs.oracle.com/javase/10/tools/jshell.htm
						# https://en.wikipedia.org/wiki/JShell
						CMD ["jshell"]
					EOD
				fi
			fi

		if [ -e "$dir/Dockerfile" ]; then
			travisEnv='\n  - VERSION='"$javaVersion"' VARIANT='"$javaVendor-$javaType $travisEnv"
		fi
		done
	done
done

travis="$(awk -v 'RS=\n\n' '$1 == "env:" { $0 = "env:'"$travisEnv"'" } { printf "%s%s", $0, RS }' .travis.yml)"
echo "$travis" > .travis.yml


