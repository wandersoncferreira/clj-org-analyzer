VERSION := 0.3.0

CLJ_FILES := $(shell find . -type f \
		\( -path "./test/*" -o -path "./dev/*" -o -path "./src/*" \) \
		\( -iname "*.clj" -o -iname "*.cljc" \) -print)

CLJS_FILES := $(shell find . -type f \
		\( -path "./test/*" -o -path "./dev/*" -o -path "./src/*" \) \
		\( -iname "*.cljs" -o -iname "*.cljc" \) -print)


# -=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-
# repl / dev

nrepl:
	clojure -R:deps:cljs:nrepl -C:cljs -C:nrepl -m org-analyzer.nrepl-server

chrome:
	chromium \
	  --remote-debugging-port=9222 \
	  --no-first-run \
	  --user-data-dir=chrome-user-profile

http-server:
	clojure -A:http-server ~/org

# -=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-
# cljs

JS_FILES := resources/public/cljs-out/dev/
JS_PROD_FILES := resources/public/cljs-out/prod/

$(JS_FILES): $(CLJS_FILES) deps.edn dev.cljs.edn
	clojure -A:cljs

$(JS_PROD_FILES): $(CLJS_FILES) deps.edn prod.cljs.edn
	clojure -R:cljs -A:cljs-prod

cljs: $(JS_FILES)

cljs-prod: $(JS_PROD_FILES)

# -=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-
# packaging / jar

pom.xml: deps.edn
	clojure -Spom

AOT := target/classes

$(AOT): $(CLJ_FILES) $(CLJS_FILES)
	mkdir -p $(AOT)
	clojure -A:aot

JAR := target/org-analyzer-$(VERSION).jar
$(JAR): cljs $(AOT) pom.xml
	mkdir -p $(dir $(JAR))
	clojure -C:http-server:aot -A:depstar -m hf.depstar.uberjar $(JAR) -m org_analyzer.http_server
	chmod a+x $(JAR)

jar: $(JAR)

run-jar: jar
	cp $(JAR) org-analyzer-el/org-analyzer.jar
	java -jar $(JAR) -m org-analyzer.http-server

# -=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-
# graal

RESOURCE_CONFIG := target/graal-resource-config.json

$(RESOURCE_CONFIG): $(CLJS_FILES)
	clojure -A:graal-prep

BIN := bin/run

$(BIN): $(AOT) cljs $(CLJS_FILES) $(CLJ_FILES) $(RESOURCE_CONFIG)
	mkdir -p bin
	native-image \
		--report-unsupported-elements-at-runtime \
		--verbose \
		--no-server \
		--initialize-at-build-time \
		-cp $(shell clojure -C:aot:http-server -Spath) \
		--no-fallback \
		--enable-http --enable-https --allow-incomplete-classpath \
		-H:+ReportExceptionStackTraces \
		-H:ResourceConfigurationFiles=$(RESOURCE_CONFIG) \
		org_analyzer.http_server \
		$(BIN)
	cp -r resources/public $(dir $(BIN))/public

bin: $(BIN)

run-bin: bin
	$(BIN)


# -=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-
# emacs

EMACS_PACKAGE_NAME:=org-analyzer-for-emacs-$(VERSION)
EMACS_PACKAGE_DIR:=/tmp/$(EMACS_PACKAGE_NAME)

update-version:
	sed -e "s/[0-9].[0-9].[0-9]/$(VERSION)/" -i org-analyzer-el/org-analyzer-pkg.el

emacs-package: $(EMACS_PACKAGE_DIR)
	mkdir -p target
	tar czvf target/$(EMACS_PACKAGE_NAME).tar.gz \
		-C $(EMACS_PACKAGE_DIR)/.. $(EMACS_PACKAGE_NAME)

$(EMACS_PACKAGE_DIR): update-version $(JAR)
	@mkdir -p $@
	cp -r org-analyzer-el/*el org-analyzer-el/*jar $@

# -=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-

clean:
	rm -rf target/$(EMACS_PACKAGE_NAME).tar.gz \
		$(EMACS_PACKAGE_DIR) \
		target .cpcache $(AOT) \
		$(JAR) bin \

.PHONY: nrepl chrome clean run-jar cljs cljs-prod http-server
