#!/bin/bash

declare aur=0
declare setup=1
declare pkg=""
declare user=""
declare rootdir=""

installPackage ()
{
	cd "$pkg" || exit 1

	su "$user" -c "makepkg -s" || exit 1
	pacman -U --noconfirm ./*.zst || exit 1

	cd - || exit 1
}

installFromAUR ()
{
	git clone "https://aur.archlinux.org/$pkg"
	installDependencies
	installPackage
}

installDependencies ()
{
	chmod 777 "$pkg" # Not recommended but the image is killed on exit
	cd "$pkg" || exit 1

	local -r srcinfo="$(su "$user" -c "makepkg --printsrcinfo")"
	local -r depends="$(echo "$srcinfo" | grep 'depends' | sed 's/.*= \|:.*//g')"
	local -a to_install=()

	for dep in $depends
	do
		echo "==> Finding $dep origin..."

		if pacman -Sp "$dep" 1>/dev/null 2>&1
		then
			echo "  -> Found in pacman repositories"
			to_install+=("$dep")
		else
			# If we have the pkgbuild in the repository
			local -r dircount="$( \
				find "$rootdir" -maxdepth 1 -name "*$dep" | wc -l 1>/dev/null 2>&1 \
			)"

			if [[ "$dircount" != "0" ]]
			then
				echo "  -> Found in our repository"
				echo ":: Switching installation to $dep"

				cd "$rootdir/$dep" || exit 1
				$0 -nosetup pkg="$dep" user="$user"
				cd - || exit 1

				echo ":: Returned from installing $dep, back to $pkg"
			else
				echo "  -> Found in the AUR"
				echo ":: Switching installation to $dep"
				$0 -nosetup -aur pkg="$dep" user="$user"
				echo ":: Returned from installing $dep, back to $pkg"
			fi
		fi
	done

	echo ":: Finished finding dependencies for $pkg, installing..."
	pacman -S --noconfirm --asdeps ${to_install/,/} || exit 1
	cd - || exit 1
}

installPackageAndDependencies ()
{
	cd "$(echo "$0" | sed 's/\/[^\/]\+//')" || exit 1
	rootdir="$(pwd)"

	installDependencies
	installPackage "$pkg"
	pacman --noconfirm -Rcns $(pacman -Qtdq)
}

setupContainer ()
{
	groupadd -f arch
	useradd -m -G arch -s /bin/bash manim
	pacman -Sy

	local -a dependencies=()

	pacman -Q git  || dependencies+=('git') 1>/dev/null 2>&1
	pacman -Q sudo || dependencies+=('sudo') 1>/dev/null 2>&1

	pacman -Syuu --noconfirm ${dependencies[*]/,/}
}

parseArgs ()
{
	while [[ $# -gt 0 ]]
	do
		local -r arg="$1"
		local -r name="${arg/=.*//}"
		local -r value="${arg/.*=//}"

		case "$name"
		in
		-aur)
			aur=1
		;;
		-nosetup)
			setup=0
		;;
		pkg)
			pkg="$value"
		;;
		user)
			user="$value"
		;;
		esac

		echo ":: Found argument: name = $name --- value = $value"
		shift
	done
}

main ()
{
	parseArgs "$@"
	[[ $setup -eq 1 ]] && setupContainer

	echo ":: Starting installation process for $pkg..."

	if [[ $aur -eq 1 ]]
	then
		installFromAUR
	else
		installPackageAndDependencies
	fi

	echo ":: Successfully finished $pkg installation!"
}

main "$@"
