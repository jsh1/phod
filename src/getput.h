/*

getput.h

Author: Tatu Ylonen <ylo@cs.hut.fi>

Copyright (c) 1995 Tatu Ylonen <ylo@cs.hut.fi>, Espoo, Finland
                   All rights reserved

Created: Wed Jun 28 22:36:30 1995 ylo

Macros for storing and retrieving data in msb first and lsb first order.

*/

/*
 * $Id: getput.h,v 1.1 2002/08/15 23:15:48 ttraffic Exp $
 * $Log: getput.h,v $
 * Revision 1.1  2002/08/15 23:15:48  ttraffic
 *
 * Importing TracerouteDB into TTM CVS
 *
 * Revision 1.1.1.1  1996/02/18  21:38:11  ylo
 *      Imported ssh-1.2.13.
 *
 * Revision 1.2  1995/07/13  01:24:09  ylo
 *      Removed "Last modified" header.
 *      Added cvs log.
 *
 * $Endlog$
 */

#ifndef GETPUT_H
#define GETPUT_H

#include <stdint.h>

/*------------ macros for storing/extracting msb first words -------------*/

#define GET_32BIT(cp) (((uint32_t)(uint8_t)(cp)[0] << 24) | \
                       ((uint32_t)(uint8_t)(cp)[1] << 16) | \
                       ((uint32_t)(uint8_t)(cp)[2] << 8) | \
                       ((uint32_t)(uint8_t)(cp)[3]))

#define GET_16BIT(cp) (((uint32_t)(uint8_t)(cp)[0] << 8) | \
                       ((uint32_t)(uint8_t)(cp)[1]))

#define PUT_32BIT(cp, value) do { \
  (cp)[0] = (value) >> 24; \
  (cp)[1] = (value) >> 16; \
  (cp)[2] = (value) >> 8; \
  (cp)[3] = (value); } while (0)

#define PUT_16BIT(cp, value) do { \
  (cp)[0] = (value) >> 8; \
  (cp)[1] = (value); } while (0)

/*------------ macros for storing/extracting lsb first words -------------*/

#define GET_32BIT_LSB_FIRST(cp) \
  (((uint32_t)(uint8_t)(cp)[0]) | \
  ((uint32_t)(uint8_t)(cp)[1] << 8) | \
  ((uint32_t)(uint8_t)(cp)[2] << 16) | \
  ((uint32_t)(uint8_t)(cp)[3] << 24))

#define GET_16BIT_LSB_FIRST(cp) \
  (((uint32_t)(uint8_t)(cp)[0]) | \
  ((uint32_t)(uint8_t)(cp)[1] << 8))

#define PUT_32BIT_LSB_FIRST(cp, value) do { \
  (cp)[0] = (value); \
  (cp)[1] = (value) >> 8; \
  (cp)[2] = (value) >> 16; \
  (cp)[3] = (value) >> 24; } while (0)

#define PUT_16BIT_LSB_FIRST(cp, value) do { \
  (cp)[0] = (value); \
  (cp)[1] = (value) >> 8; } while (0)

#endif /* GETPUT_H */


