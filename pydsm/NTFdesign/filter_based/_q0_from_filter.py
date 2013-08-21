# -*- coding: utf-8 -*-

# Copyright (c) 2012, Sergio Callegari
# All rights reserved.

"""
Functions to obtain the matrix used in the NTF optimization
===========================================================

The matrix is symmetric Toeplitz, thus actually described by its first
row only, which is what the routines here return.
"""

from ...correlations import raw_acorr
from ...ft import idtft_hermitian
from ..weighting import q0_from_noise_weighting
import numpy as np

__all__=["q0_from_filter_imp_response", "q0_from_filter_mag_response"]

def q0_from_filter_imp_response(P, h_ir):
    """
    Computes Q matrix from the output filter impulse response

    Parameters
    ----------
    P : int
        order of the FIR to be eventually synthesized
    h_ir : array_like
        impulse response of the filter

    Returns
    -------
    q0 : ndarray
        the first row of the matrix Q used in the NTF optimization

    Notes
    -----
    The Q matrix being synthesized has (P+1) times (P+1) entries.
    """
    return raw_acorr(h_ir, P)

def q0_from_filter_mag_response(P, h_mag,\
    integrator_params={'epsabs':1E-14, 'epsrel':1E-9}):
    """
    Computes Q matrix from the output filter magnitude response

    Parameters
    ----------
    P : int
        order of the FIR to be eventually synthesized
    h_mag : callable
        function of f representing the filter magnitude response
        f is normalized between 0 and 0.5

    Returns
    -------
    q0 : ndarray
        the first row of the matrix Q used in the NTF optimization

    Other parameters
    ----------------
    integrator_params : dict, optional
        the controlling parameters for the numerical integrator
        (see `scipy.integrate.quad`)

    Notes
    -----
    The Q matrix being synthesized has (P+1) times (P+1) entries.
    """
    h_mag2=lambda f: h_mag(f)**2
    return q0_from_noise_weighting(P, h_mag2, integrator_params)