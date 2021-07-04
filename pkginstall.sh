#!/bin/sh

pkg=""
user=""
rootdir=""

installPackage ()
{
	installpkg="$1"

	cd "$installpkg" || exit 1

	su "$user" -c "makepkg -s" || exit 1
	pacman -U --noconfirm ./*.zst || exit 1

	cd - || exit 1
}

installFromAUR ()
{
	aurpkg="$1"

	git clone "https://aur.archlinux.org/$aurpkg"
	installDependencies "$aurpkg"
}

installDependencies ()
{
	currentpkg="$1"
	chmod 777 "$currentpkg" # Not recommended but the image is killed on exit
	cd "$currentpkg" || exit 1

	srcinfo="$(su "$user" -c "makepkg --printsrcinfo")"
	depends="$(echo "$srcinfo" | grep 'depends' | sed 's/.*= \|:.*//g')"
	to_install=""

	for dep in $depends
	do
		echo "==> Finding $dep origin..."

		if pacman -Sp "$dep" 1>/dev/null 2>&1
		then
			echo "  -> Found in pacman repositories"
			to_install="$to_install $dep"
		else
			# If we have the pkgbuild in the repository
			if find "$rootdir" -maxdepth 1 -name "*$dep" 1>/dev/null 2>&1
			then
				echo "  -> Found in our repository"
				echo ":: Switching installation to $dep"

				cd "$rootdir/$dep" || exit 1
				$0 pkg="$dep" user="$user"
				cd - || exit 1

				echo ":: Returned from installing $dep, back to $currentpkg"
			else
				echo "  -> Found in the AUR"
				echo ":: Switching installation to $dep"
				installFromAUR "$dep"
				echo ":: Returned from installing $dep, back to $currentpkg"
			fi
		fi
	done

	echo ":: Finished finding dependencies for $currentpkg, installing..."
	pacman -S --noconfirm --asdeps $to_install || exit 1
	cd - || exit 1
}

installPackageAndDependencies ()
{
	currentpkg="$1"
	cd "$(echo "$0" | sed 's/\/[^\/]\+//')" || exit 1
	rootdir="$(pwd)"

	installDependencies "$currentpkg"
	installPackage "$currentpkg"
	pacman --noconfirm -Rcns $(pacman -Qtdq)
}

setupContainer ()
{
	groupadd -f arch
	useradd -m -G arch -s /bin/bash manim
	pacman -Sy

	dependencies=""

	pacman -Q git  || dependencies="$dependencies git" 1>/dev/null 2>&1
	pacman -Q sudo || dependencies="$dependencies sudo" 1>/dev/null 2>&1

	pacman -Syuu --noconfirm $dependencies
}

parseArgs ()
{
	while [ $# -gt 0 ]
	do
		arg="$1"
		name="$(echo "$arg" | sed 's/=.*//')"
		value="$(echo "$arg" | sed 's/.*=//')"

		case "$name"
		in
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
	setupContainer

	echo ":: Starting installation process for $pkg..."

	installPackageAndDependencies "$pkg"

	echo ":: Successfully finished $pkg installation!"
}

main "$@"
