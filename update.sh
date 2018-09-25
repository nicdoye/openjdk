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

	EOD
}

travisEnv=
for javaVersion in "${versions[@]}"; do
	for javaType in jdk jre; do
		dir="$javaVersion/$javaType"

		suite="${suites[$javaVersion]:-}"
		if [ -n "$suite" ]; then
			addSuite="${addSuites[$javaVersion]:-}"

			needCaHack=
			if [ "$javaVersion" -ge 8 -a "$suite" != 'sid' ]; then
				# "20140324" is broken (jessie), but "20160321" is fixed (sid)
				needCaHack=1
			fi

			# FIXME
			debianPackage="openjdk-$javaVersion-$javaType"
			debSuite="${addSuite:-$suite}"
			debian-latest-version "$debianPackage" "$debSuite" > /dev/null # prime the cache
			debianVersion="$(debian-latest-version "$debianPackage" "$debSuite")"
			fullVersion="${debianVersion%%-*}"
			fullVersion="${fullVersion#*:}"

			tilde='~'
			case "$javaVersion" in
				11)
					# update Debian's "11~8" to "11-ea+8" (matching http://jdk.java.net/11/)
					fullVersion="${fullVersion//$javaVersion$tilde/$javaVersion-ea+}"
					;;
			esac
			fullVersion="${fullVersion//$tilde/-}"

			echo "$javaVersion-$javaType: $fullVersion (debian $debianVersion)"

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

			if [ "$addSuite" ]; then
				cat >> "$dir/Dockerfile" <<-EOD

					RUN echo 'deb http://deb.debian.org/debian $addSuite main' > /etc/apt/sources.list.d/$addSuite.list
				EOD
			fi

			cat >> "$dir/Dockerfile" <<-EOD

				# Set the locale
				ENV LANG en_US.UTF-8
				ENV LANGUAGE en_US:en
				ENV LC_ALL en_US.UTF-8
				ENV JAVA_HOME=/usr/java/default
	
			EOD

			template-java-home-script >> "$dir/Dockerfile"



			cat >> "$dir/Dockerfile" <<EOD
# This used to be serverjre-*.tar.gz (and not an ARG)
# now it will be serverjre-8u181-bin.tar.gz / serverjre-11.0.0-bin.tar.gz
ENV JAVA_PKG="\$JAVA_PKG"
ADD $JAVA_PKG /usr/java/

RUN export JAVA_DIR=$(ls -1 -d /usr/java/*) && \\
    ln -s $JAVA_DIR /usr/java/latest && \\
    ln -s $JAVA_DIR /usr/java/default && \\
    alternatives --install /usr/bin/java java $JAVA_DIR/bin/java 20000 && \\
    alternatives --install /usr/bin/javac javac $JAVA_DIR/bin/javac 20000 && \\
    alternatives --install /usr/bin/jar jar $JAVA_DIR/bin/jar 20000
EOD

			if [ "$needCaHack" ]; then
				cat >> "$dir/Dockerfile" <<-EOD

				# see CA_CERTIFICATES_JAVA_VERSION notes above
				RUN /var/lib/dpkg/info/ca-certificates-java.postinst configure
				EOD
			fi

			if [ "$javaType" = 'jdk' ] && [ "$javaVersion" -ge 10 ]; then
				cat >> "$dir/Dockerfile" <<-'EOD'

					# https://docs.oracle.com/javase/10/tools/jshell.htm
					# https://en.wikipedia.org/wiki/JShell
					CMD ["jshell"]
				EOD
			fi

			template-contribute-footer >> "$dir/Dockerfile"
		fi
	done

	if [ -e "$javaVersion/jdk/Dockerfile" ]; then
		travisEnv='\n  - VERSION='"$javaVersion$travisEnv"
	fi
done

travis="$(awk -v 'RS=\n\n' '$1 == "env:" { $0 = "env:'"$travisEnv"'" } { printf "%s%s", $0, RS }' .travis.yml)"
echo "$travis" > .travis.yml


