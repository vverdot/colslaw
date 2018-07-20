# Get a resource
xrdb -n .Xresources.d/rxvt-solarized.light | grep background | cut -f2

# Install extension

```
mkdir -p "$HOME/.urxvt/ext/"
ln -s "$(realpath colslaw.pl)" "$HOME/.urxvt/ext/colslaw"
```
