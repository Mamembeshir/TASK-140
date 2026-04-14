SCHEME = ForgeFlow
DEST = 'platform=iOS Simulator,name=iPhone 16 Pro,OS=18.6'

.PHONY: build test test-unit test-integration test-views clean

build:
	xcodebuild -scheme $(SCHEME) -destination $(DEST) build

test:
	xcodebuild -scheme $(SCHEME) -destination $(DEST) test

test-unit:
	xcodebuild -scheme $(SCHEME) -destination $(DEST) -only-testing:ForgeFlowTests/UnitTests test

test-integration:
	xcodebuild -scheme $(SCHEME) -destination $(DEST) -only-testing:ForgeFlowTests/IntegrationTests test

test-views:
	xcodebuild -scheme $(SCHEME) -destination $(DEST) -only-testing:ForgeFlowTests/ViewTests test

clean:
	xcodebuild -scheme $(SCHEME) clean
