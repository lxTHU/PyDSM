# -*- coding: utf-8 -*-

# Copyright (c) 2012, Sergio Callegari
# All rights reserved.

# This file is part of PyDSM.

# PyDSM is free software: you can redistribute it and/or modify it
# under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 3 of the License, or
# (at your option) any later version.

# PyDSM is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.

# You should have received a copy of the GNU General Public License
# along with PyDSM.  If not, see <http://www.gnu.org/licenses/>.

"""
Fast simulator for a generic delta sigma modulator using scipy blas
===================================================================
"""

import numpy as np
cimport numpy as np
np.import_array()
import scipy as sp
__import__('scipy.signal')
__import__('scipy.linalg')
from libc.math cimport floor, fabs

cdef extern from "23compat.h":
    void *Capsule_AsVoidPtr(object ptr)

ctypedef void (*dgemv_ptr) (char *trans, int *m, int *n,\
    double *alpha, double *a, int *lda, double *x, int *incx,\
    double *beta,  double *y, int *incy)
ctypedef void (*dcopy_ptr) (int *N, double *x, int *incx,\
    double *y, int*incy)
cdef dgemv_ptr dgemv=<dgemv_ptr>Capsule_AsVoidPtr(
    sp.linalg.blas.dgemv._cpointer)
cdef dcopy_ptr dcopy=<dcopy_ptr>Capsule_AsVoidPtr(
    sp.linalg.blas.dcopy._cpointer)

#cdef dgemv_ptr dgemv=<dgemv_ptr>NULL
#cdef dcopy_ptr dcopy=<dcopy_ptr>NULL

include '_simulateDSM_helper.pxi'

def simulateDSM(np.ndarray u, arg2, nlev=2, x0=0,
                int store_xn=False, int store_xmax=False, int store_y=False):

    # Make sure that nlev is a 1D int array
    cdef np.ndarray c_nlev
    try:
        c_nlev = np.asarray(nlev, dtype=np.int)
        if c_nlev.ndim > 1:
            raise TypeError()
        c_nlev=c_nlev.reshape(1)
    except (ValueError, TypeError):
         raise ValueError(\
            "Invalid argument: nlev must be convertible into a 1D int array")

    # Make sure that input is a matrix
    cdef np.ndarray c_u
    try:
        c_u = np.asarray(u, dtype=np.float64, order='C')
        if c_u.ndim > 2:
            raise TypeError()
        if c_u.ndim == 1:
            c_u = c_u.reshape(1, -1)
    except (ValueError, TypeError):
        raise ValueError(\
            "Invalid argument: u must be convertible into a 2D float array")

    cdef int nu = c_u.shape[0]
    cdef int nq = c_nlev.shape[0]

    cdef int order

    try:
        if type(arg2)==tuple and len(arg2)==3:
            # Assume ntf in zpk form
            ntf_z=np.asarray(arg2[0], dtype=np.complex128)
            ntf_p=np.asarray(arg2[1], dtype=np.complex128)
            ntf_k=float(arg2[2])
            if ntf_z.ndim !=1 or ntf_p.ndim != 1:
                raise TypeError()
            form = 2
            order = ntf_z.shape[0]
        else:
            # Assume ABCD form
            ABCD = np.asarray(arg2, dtype=np.float64)
            if ABCD.ndim!=2:
                raise TypeError()
            if ABCD.shape[1] != nu+ABCD.shape[0]:
                raise TypeError()
            form = 1
            order = ABCD.shape[0]-nq
    except (ValueError, TypeError):
        raise ValueError('Incorrect modulator specification')

    cdef np.ndarray c_x0, c_x0_temp
    # Assure that the state is a column vector
    try:
        if np.isscalar(x0) and x0 == 0:
            c_x0 = np.zeros((order, 1), dtype=np.float64)
        else:
            c_x0 = np.array(x0, dtype=np.float64, order='C')
            if c_x0.ndim < 1 or c_x0.ndim > 2:
                raise TypeError()
            c_x0=c_x0.reshape(-1, 1)
            if c_x0.shape[0]!=order:
                raise TypeError()
    except (ValueError, TypeError):
        raise ValueError('Incorrect initial condition specification')
    c_x0_temp = np.empty_like(c_x0)

    cdef np.ndarray A, B1, B2, C, D1
    # Build ISO Model
    # note that B=hstack((B1, B2))
    if form == 1:
        A = np.asarray(ABCD[0:order, 0:order], dtype=np.float64, order='C')
        B1 = np.asarray(ABCD[0:order, order:order+nu],\
            dtype=np.float64, order='C')
        B2 = np.asarray(ABCD[0:order, order+nu:order+nu+nq],\
            dtype=np.float64, order='C')
        C = np.asarray(ABCD[order:order+nq, 0:order],\
            dtype=np.float64, order='C')
        D1 = np.asarray(ABCD[order:order+nq, order:order+nu], \
            dtype=np.float64, order='C')
    else:
        # Seek a realization of -1/H
        A, B2, C, D2 = sp.signal.zpk2ss(ntf_p, ntf_z, -1)
        C=C.real
        # Transform the realization so that C = [1 0 0 ...]
        Sinv = sp.linalg.orth(np.hstack((np.transpose(C), np.eye(order))))/ \
            np.linalg.norm(C)
        S = sp.linalg.inv(Sinv)
        C = np.dot(C, Sinv)
        if C[0, 0] < 0:
            S = -S
            Sinv = -Sinv
        A = np.asarray(S.dot(A).dot(Sinv), dtype=np.float64, order='C')
        B2 = np.asarray(np.dot(S, B2), dtype=np.float64, order='C')
        C = np.asarray(np.hstack(([[1.]], np.zeros((1,order-1)))),\
            dtype=np.float64, order='C')
        # C=C*Sinv;
        # D2 = 0;
        # !!!! Assume stf=1
        B1 = -B2
        D1 = np.asarray(1., dtype=np.float64)
        #B = np.hstack((B1, B2))

    # N is number of input samples to deal with
    cdef int N = c_u.shape[1]
    # v is output vector
    cdef np.ndarray v = np.empty((nq, N), dtype=np.float64)
    cdef np.ndarray y = np.empty(0, dtype=np.float64)
    if store_y:
        # Need to store the quantizer input
        y = np.empty((nq, N), dtype=np.float64)
    cdef np.ndarray xn = np.empty(0, dtype=np.float64)
    if store_xn:
        # Need to store the state information
        xn = np.empty((order, N), dtype=np.float64)
    cdef np.ndarray xmax = np.empty(0, dtype=np.float64)
    if store_xmax:
        # Need to keep track of the state maxima
        xmax = np.abs(c_x0)

    # y0 is output before the quantizer
    cdef np.ndarray y0 = np.empty(nq, dtype=np.float64)

    cdef int i
    cdef int one=1
    cdef double onedot = 1.0
    cdef double zerodot = 0.0
    for i in xrange(N):
        # Compute y0 = np.dot(C, c_x0) + np.dot(D1, u[:, i])
        dgemv('T', &order, &nq,\
            &onedot, dbldata(C), &order, \
            dbldata(c_x0), &one, \
            &zerodot, dbldata(y0), &one)
        dgemv('T', &nu, &nq,\
            &onedot, dbldata(D1), &nu, \
            dbldata(c_u)+i, &N, \
            &onedot, dbldata(y0), &one)
        if store_y:
            #y[:, i] = y0[:]
            dcopy(&nq, dbldata(y0), &one,\
            dbldata(y)+i, &N)
        ds_quantize(nq, dbldata(y0), 1, \
            intdata(c_nlev), 1, \
            dbldata(v)+i, N)
        # Compute c_x0 = np.dot(A, c_x0) +
        #   np.dot(B, np.vstack((u[:, i], v[:, i])))
        dgemv('T', &order, &order,\
            &onedot, dbldata(A), &order, \
            dbldata(c_x0), &one,\
            &zerodot, dbldata(c_x0_temp), &one)
        dgemv('T', &nu, &order,\
            &onedot, dbldata(B1), &nu, \
            dbldata(c_u)+i, &N, \
            &onedot, dbldata(c_x0_temp), &one)
        dgemv('T', &nq, &order,\
            &onedot, dbldata(B2), &nq, \
            dbldata(v)+i, &N, \
            &onedot, dbldata(c_x0_temp), &one)
        # c_x0[:,1] = c_x0_temp[:,1]
        dcopy(&order, dbldata(c_x0_temp), &one,\
            dbldata(c_x0), &one)
        if store_xn:
            # Save the next state
            #xn[:, i] = c_x0
            dcopy(&order, dbldata(c_x0), &one,\
            dbldata(xn)+i, &N)
        if store_xmax:
            # Keep track of the state maxima
            # xmax = np.max((np.abs(x0), xmax), 0)
            track_vabsmax(order, dbldata(xmax), 1,\
                dbldata(c_x0), 1)
    if not store_xn:
        xn = c_x0
    return v.squeeze(), xn.squeeze(), xmax, y.squeeze()