#!/usr/bin/perl


sub on_sel_grab {
    warn "you selected ", $_[0]->selection;
    ()
}
