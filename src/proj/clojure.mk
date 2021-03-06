## makefile automates the build and deployment for lein projects

# edit these if you want
#GUSER=		
#APP_NAME=	
#PROJ=		
#REMOTE=		github

LEIN_PROJECT ?=	project.clj

# environment
LEIN=		lein

# defs
POM=		pom.xml
#MTARG=		target

# determine version
VER_LAST_TAG=	$(shell git tag -l | sort -V | tail -1 | sed 's/.//')
VER ?=		$(shell git describe --match v*.* --abbrev=4 --dirty=-dirty | sed 's/^v//')
VPREF=		$(if $(VER),-$(VER),-0.1.0-SNAPSHOT)

# application name (jars and dist)
ANRCMD ?=	grep '(defproject' $(LEIN_PROJECT) | head -1 | sed 's/(defproject \(.*\)\/\(.*\) .*/\2/'
ANRRES ?=	$(shell $(ANRCMD))
APP_NAME_REF ?=	$(if $(APP_NAME),$(APP_NAME),$(ANRRES))
APP_SNAME_REF ?= $(if $(APP_SCR_NAME),$(APP_SCR_NAME),$(APP_NAME_REF))

# main class
MC_CMD=		grep -E '\s+:main\s+' $(LEIN_PROJECT) | head -1 | sed 's/.*:main \(.*\)).*/\1/'
MAIN_CLASS ?=	$(shell $(MC_CMD))

# jar
LIB_JAR_NAME=	$(ANRRES)$(VPREF).jar
LIB_JAR=	$(MTARG)/$(LIB_JAR_NAME)
UBER_JAR_NAME=	$(ANRRES)$(VPREF)-standalone.jar
UBER_JAR=	$(MTARG)/$(UBER_JAR_NAME)
UBER_JAR_PROFS+=with-profile +uberjar

# git
GITREMOTE=	$(if $(REMOTE),$(REMOTE),github)
PNCMD=		git remote -v | grep $(GITREMOTE) | grep push | sed -e 's:^.*/\(.*\) (push):\1:' -e 's:.git$$::'
PROJ_REF=	$(if $(PROJ),$(PROJ),$(shell $(PNCMD)))
USRCMD=		git remote -v | grep $(GITREMOTE) | grep push | sed 's/.*\/\(.*\)\/.*/\1/'
GITUSER=	$(if $(GUSER),$(GUSER),$(shell $(USRCMD)))

# doc
DOC_SRC_DIR=	./doc
# codox
DOC_DST_DIR=	$(MTARG)/doc

# executables
GTAGUTIL=	$(ZBHOME)/src/python/gtagutil
AWSENV=		$(ZBHOME)/src/python/awsenv

# deploy
DEPLOY_REPO ?=	clojars
ifeq ($(DEPLOY_REPO),clojars)
DEPLOY_CMD=	$(LEIN) deploy $(DEPLOY_REPO)
else
DEPLOY_CMD=	$(AWSENV) $(LEIN) deploy $(DEPLOY_REPO)
endif

# auto generated file
CLJ_PVER=	$(shell grep -E '\s+:path\s+"src/clojure' $(LEIN_PROJECT) | head -1 | sed 's/.*:path[ \t]*"\(.*\)".*/\1/')
CLJ_VERSION=	$(if $(CLJ_PVER),$(CLJ_PVER)/version.clj,src/clojure/$(APP_NAME_REF)/version.clj)

# clean setup
ADD_CLEAN +=	$(POM)* .nrepl-port .lein-repl-history dev-resources $(CLJ_VERSION)


# targets
.PHONY: compile
compile:	$(LIB_JAR)

.PHONY:	javac
javac:
		$(LEIN) javac

.PHONY: jar
jar:		$(LIB_JAR)

.PHONY: install
install:	$(COMP_DEPS)
	$(LEIN) install

.PHONY: snapshot
snapshot:	$(COMP_DEPS)
	@grep ':snapshot' $(LEIN_PROJECT) > /dev/null ; \
		if [ $$? == 1 ] ; then \
			echo "no snapshot profile found in $(LEIN_PROJECT)" ; \
			false ; \
		fi
	$(LEIN) with-profile +snapshot install

.PHONY: uber
uber:		$(UBER_JAR)

.PHONY:	cleanuber
cleanuber:
	rm -f $(LIB_JAR) $(UBER_JAR)

.PHONY: deploy
deploy:	checkver
	$(DEPLOY_CMD)

.PHONY: run
run:
	$(LEIN) run

.PHONY: init
init:
	git init .
	git add -A :/
	git commit -am 'initial commit'
	$(GTAGUTIL) create -m 'initial release'

.PHONY: forcetag
forcetag:
	git add -A :/
	git commit -am 'none' || echo "not able to commit"
	$(GTAGUTIL) recreate

.PHONY: forcepush
forcepush:
	git push
	git push --tags --force

.PHONY: newtag
newtag:
	$(GTAGUTIL) create -m '`git log -1 --pretty=%B`'

.PHONY: info
info:
	@echo "version: $(VER)"
	@echo "comp-deps: $(COMP_DEPS)"
	@echo "project: $(PROJ_REF)"
	@echo "remote: $(GITREMOTE)"
	@echo "user: $(GITUSER)"
	@echo "jar: $(LIB_JAR)"
	@echo "uberjar: $(UBER_JAR)"
	@echo "app-script: $(APP_SNAME_REF)"
	@echo "app-dist: $(DIST_DIR)"
	@echo "app-main-class: $(MAIN_CLASS)"
	@echo "clj-version-file: $(CLJ_VERSION)"
	@echo "deploy: $(DEPLOY_CMD)"
	@echo "make-include: $(BUILD_INC)"

.PHONY: mvndeptree
mvndeptree:	$(POM)
	mvn dependency:tree -D verbose

.PHONY: deptree
deptree:
	lein deps :tree

.PHONY:	deps
deps:
	$(AWSENV) $(LEIN) deps

$(LIB_JAR):	$(COMP_DEPS)
	@echo compiling $(LIB_JAR)
	$(LEIN) jar

$(UBER_JAR):	$(COMP_DEPS)
	@echo compiling $(UBER_JAR)
	$(LEIN) $(UBER_JAR_PROFS) uberjar

.PHONY: checkdep
checkdep:
	@echo compiling $(UBER_JAR)
	$(LEIN) with-profile +appassem uberjar

.PHONY: checkver
checkver:
	@echo $(VER_LAST_TAG) =? $(VER) ; [ "$(VER_LAST_TAG)" == "$(VER)" ]

.PHONY:	leintest
leintest:
	$(LEIN) test

.PHONY:	check
check:	checkver leintest checkdep

$(POM):
	$(LEIN) pom

.PHONY: docs
docs:	$(DOC_DST_DIR)

# https://github.com/weavejester/codox/wiki/Deploying-to-GitHub-Pages
$(DOC_DST_DIR):
	rm -rf $(DOC_DST_DIR) && mkdir -p $(DOC_DST_DIR)
	git clone https://github.com/$(GITUSER)/$(PROJ_REF).git $(DOC_DST_DIR)
	git update-ref -d refs/heads/gh-pages 
	( cd $(DOC_DST_DIR) ; \
	  git symbolic-ref HEAD refs/heads/gh-pages ; \
	  rm .git/index ; \
	  git clean -fdx )
	if [ -d $(DOC_SRC_DIR) ] ; then cp -r $(DOC_SRC_DIR)/* $(DOC_DST_DIR) ; fi
	[ -d src/java ] && $(LEIN) javadoc || true
	$(LEIN) $(LEIN_DOC_PROFS) codox

.PHONY: pushdocs
pushdocs:	checkver $(DOC_DST_DIR)
	git push $(GITREMOTE) --mirror
	( cd $(DOC_DST_DIR) ; \
	  git add . ; \
	  git commit -am "new doc push" ; \
	  git push -u origin gh-pages )
