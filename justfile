# Justfile for TachikomaDemos

# Default task
default:
	@just --list

# Run the demo launcher in a local terminal
terminal:
	julia --project=demos/TachikomaDemos -e 'using TachikomaDemos; launcher()'

# Run a specific demo in a local terminal (e.g., just run-demo snake)
run-demo DEMO_NAME:
	julia --project=demos/TachikomaDemos -e 'using TachikomaDemos; run_demo(TachikomaDemos.{{DEMO_NAME}})'

# Run a specific demo in the web browser (e.g., just web-demo snake)
web-demo DEMO_NAME PORT="8000":
	julia --project=demos/TachikomaDemos -e 'using Pkg; Pkg.add("HTTP"); using TachikomaDemos, HTTP; browser(TachikomaDemos.{{DEMO_NAME}}; port={{PORT}})'

# Run the demo launcher in the web browser
webterminal PORT="8000":
	julia --project=demos/TachikomaDemos -e 'using Pkg; Pkg.add("HTTP"); using TachikomaDemos, HTTP; browser(launcher; port={{PORT}})'
