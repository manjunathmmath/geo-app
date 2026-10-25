package com.geoapp.users;

/** Anonymous visitors have no account; every registered user is a CREATOR unless promoted. */
public enum Role {
    CREATOR,
    ADMIN
}
