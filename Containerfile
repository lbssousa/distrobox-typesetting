# Typesetting/music-engraving toolchain image for use with `distrobox create
# --image`. See README.md for the accompanying build/create wrapper script
# and the full list of configuration options.

ARG BASE_IMAGE=alpine:latest
FROM ${BASE_IMAGE}

ARG TEXLIVE_RELEASE=latest
ARG TEXLIVE_SCHEME=minimal
# Temporary trimmed-down default while iterating on the build: the "minimal"
# scheme plus the extra packages listed by AISCGre-BR's
# Eugene-Cardine-Primeiro-Ano-de-Semiologia-Gregoriana project, plus the
# individual packages MusiXTeX needs (musixtex, musixtex-fonts).
ARG TEXLIVE_PACKAGES="babel-latin,babel-portuges,booktabs,csquotes,ebgaramond,enumitem,epstopdf-pkg,float,fontspec,geometry,hyperref,hyphen-latin,hyphen-portuguese,l3packages,latex-bin,latexindent,latexmk,libertine,listings,luacolor,luamplib,luatex85,luatexbase,memoir,metapost,metre,microtype,musixtex,musixtex-fonts,paracol,pgf,quoting,relsize,stackengine,standalone,subfiles,texcount,textcase,tikzmark,tools,varwidth,xcolor,xetex,xkeyval,xpatch,xstring"
ARG TEXLIVE_MIRROR=https://linorg.usp.br
ARG LILYPOND_VERSION=2.26.0
ARG GREGORIO_REF=playground-2026-08-27

COPY scripts/ /opt/distrobox-typesetting/scripts/
COPY container-bin/ /usr/local/bin/
RUN chmod +x \
    /opt/distrobox-typesetting/scripts/*.sh \
    /opt/distrobox-typesetting/scripts/lib/*.sh \
    /usr/local/bin/update-*

RUN RELEASE="${TEXLIVE_RELEASE}" SCHEME="${TEXLIVE_SCHEME}" PACKAGES="${TEXLIVE_PACKAGES}" \
    MIRROR="${TEXLIVE_MIRROR}" \
    /opt/distrobox-typesetting/scripts/install-texlive.sh

RUN VERSION="${LILYPOND_VERSION}" \
    /opt/distrobox-typesetting/scripts/install-lilypond.sh

RUN HOST=github REPOSITORY=lbssousa/gregorio REF="${GREGORIO_REF}" \
    /opt/distrobox-typesetting/scripts/install-gregorio.sh

RUN /opt/distrobox-typesetting/scripts/install-inkscape.sh
RUN /opt/distrobox-typesetting/scripts/install-svg2tikz.sh
RUN /opt/distrobox-typesetting/scripts/install-neovim.sh
RUN /opt/distrobox-typesetting/scripts/install-zathura.sh
RUN /opt/distrobox-typesetting/scripts/configure-fonts.sh

ENV MANPATH="/opt/texlive/bin/man:${MANPATH}" \
    INFOPATH="/opt/texlive/bin/info:${INFOPATH}"
