/* Copyright (C) 2004, 2008  Matthijs van Duin.  All rights reserved.
 * Copyright (C) 2014, 2015 cPanel Inc.  All rights reserved.
 * This program is free software; you can redistribute it and/or modify
 * it under the same terms as Perl itself.
 */

#include "EXTERN.h"
#include "perl.h"
#include "XSUB.h"

#define NEED_newSVpvn_flags
#define NEED_sv_2pv_flags
#include "ppport.h"
/* Not in ppport yet: */
#ifndef HvNAMEUTF8
#  define HvNAMEUTF8(hv)		0
#endif

static MGVTBL subname_vtbl;

MODULE = Sub::Name  PACKAGE = Sub::Name

PROTOTYPES: DISABLE

void
subname(name, sub)
	SV *name
	SV *sub
    PREINIT:
	CV *cv = NULL;
	GV *gv;
	HV *stash = CopSTASH(PL_curcop);
        char *s, *last, *end = NULL;
	MAGIC *mg;
        STRLEN len;
    PPCODE:
	if (!SvROK(sub) && SvGMAGICAL(sub))
		mg_get(sub);
	if (SvROK(sub))
		cv = (CV *) SvRV(sub);
	else if (SvTYPE(sub) == SVt_PVGV)
		cv = GvCVu(sub);
	else if (!SvOK(sub))
		croak(PL_no_usym, "a subroutine");
	else if (PL_op->op_private & HINT_STRICT_REFS)
		croak("Can't use string (\"%.256s\") as %s ref while \"strict refs\" in use",
		      SvPV_nolen(sub), "a subroutine");
	else if ((gv = gv_fetchpvn_flags(SvPV_nolen(sub), SvCUR(sub), FALSE, SVt_PVCV)))
		cv = GvCVu(gv);
	if (!cv)
		croak("Undefined subroutine %.256s", SvPV_nolen(sub));
	if (SvTYPE(cv) != SVt_PVCV && SvTYPE(cv) != SVt_PVFM)
		croak("Not a subroutine reference");
        last = s = SvPVX(name);
        last += SvCUR(name);
        /* TODO: If there exists a UTF8 codepoint with ending ':' we are screwed. But perl5 does not care neither. */
        for (; s < last; s++) {
		if (*s == ':' && s[-1] == ':')
			end = ++s;
                /* "In the year 2525, if man is still alive
                   If 4 is finally gone" - gv.c:S_parse_gv_stash_name */
#if PERL_VERSION < 25
		else if (*s && s[-1] == '\'')
			end = s;
#endif
	}
        if (end) {
                int flags = GV_ADD;
                const int stash_len = end - SvPVX(name);
#if PERL_VERSION <= 8
                /* <= 5.8.8 needs a copy */
                SV *tmpbuf = newSVpvn(SvPVX(name), stash_len);
#endif
#if PERL_VERSION >= 10
                flags |= SvUTF8(name);
#endif
                len = s - end;
#if PERL_VERSION <= 8
		stash = GvHV(gv_fetchpv(SvPVX(tmpbuf), flags, SVt_PVHV));
                SvREFCNT_dec(tmpbuf);
#else
		stash = GvHV(gv_fetchpvn_flags(SvPVX(name), stash_len, flags, SVt_PVHV));
#endif
                s = end;
        } else {
        	len = s - SvPVX(name);
                s = SvPVX(name);
        }
#if defined(DEBUGGING) && defined(I_ASSERT)
        assert(len >= 0);
#endif

	/* under debugger, provide information about sub location */
	if (PL_DBsub && CvGV(cv)) {
		HV *hv = GvHV(PL_DBsub);
                GV *oldgv = CvGV(cv);
                HV *oldpkg = GvSTASH(oldgv);
                SV *full_name = newSVpvn_flags(HvNAME(oldpkg), HvNAMELEN_get(oldpkg),
                                               HvNAMEUTF8(oldpkg));
		SV** old_data;

                sv_catpvs(full_name, "::");
                sv_catpvn(full_name, GvNAME(oldgv), GvNAMELEN(oldgv));

		old_data = hv_fetch(hv, SvPVX(full_name), SvCUR(full_name), 0);

		if (old_data) {
                        full_name = newSVpvn_flags(HvNAME(stash), HvNAMELEN_get(stash),
                                                   HvNAMEUTF8(stash));
                        sv_catpvs(full_name, "::");
                        sv_catpvn(full_name, s, len);

                        SvREFCNT_inc(*old_data);
                        if (!hv_store(hv, SvPVX(full_name), SvCUR(full_name), *old_data, 0))
                            SvREFCNT_dec(*old_data);
		}
		SvREFCNT_dec(full_name);
	}

	gv = (GV *) newSV(0);
#if PERL_VERSION >= 16
        gv_init_pvn(gv, stash, s, len, SvUTF8(name));
#else
        gv_init(gv, stash, s, len, GV_ADD);
/* Nope. This old B can not handle this negative HEK_LEN, leaves it negative. */
#if 0 && PERL_VERSION >= 10
        if (SvUTF8(name)) {
            HEK *namehek = GvNAME_HEK(gv);
            HEK_LEN(namehek) = -abs(HEK_LEN(namehek));
            SvUTF8_on(gv);
        }
#endif
#endif

	mg = SvMAGIC(cv);
	while (mg && mg->mg_virtual != &subname_vtbl)
		mg = mg->mg_moremagic;
	if (!mg) {
		Newxz(mg, 1, MAGIC);
		mg->mg_moremagic = SvMAGIC(cv);
		mg->mg_type = PERL_MAGIC_ext;
		mg->mg_virtual = &subname_vtbl;
		SvMAGIC_set(cv, mg);
	}
	if (mg->mg_flags & MGf_REFCOUNTED)
		SvREFCNT_dec(mg->mg_obj);
	mg->mg_flags |= MGf_REFCOUNTED;
	mg->mg_obj = (SV *) gv;
	SvRMAGICAL_on(cv);
	CvANON_off(cv);
#ifndef CvGV_set
	CvGV(cv) = gv;
#else
	CvGV_set(cv, gv);
#endif
	PUSHs(sub);
