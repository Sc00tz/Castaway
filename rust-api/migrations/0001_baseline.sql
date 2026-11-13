-- Castaway's database schema, as of the move to PostgreSQL-only (2026-11).
--
-- Generated from the final PinePods-era migrations (schema version 118), so a database those
-- migrations built already matches it. Later schema changes go in new numbered files.

--
-- Name: AISettings; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public."AISettings" (
    aisettingsid integer NOT NULL,
    transcriptionmodel character varying(100) DEFAULT 'base'::character varying NOT NULL,
    llmbackend character varying(20) DEFAULT 'local'::character varying NOT NULL,
    llmmodel character varying(200),
    llmurl character varying(500),
    llmapikey text,
    whisperdevice character varying(20) DEFAULT 'cpu'::character varying NOT NULL,
    whispercomputetype character varying(20) DEFAULT 'int8'::character varying NOT NULL,
    updatedat timestamp without time zone DEFAULT CURRENT_TIMESTAMP NOT NULL
);

--
-- Name: AISettings_aisettingsid_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public."AISettings_aisettingsid_seq"
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;

--
-- Name: AISettings_aisettingsid_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public."AISettings_aisettingsid_seq" OWNED BY public."AISettings".aisettingsid;

--
-- Name: APIKeys; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public."APIKeys" (
    apikeyid integer NOT NULL,
    userid integer,
    apikey text,
    created timestamp without time zone DEFAULT CURRENT_TIMESTAMP
);

--
-- Name: APIKeys_apikeyid_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public."APIKeys_apikeyid_seq"
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;

--
-- Name: APIKeys_apikeyid_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public."APIKeys_apikeyid_seq" OWNED BY public."APIKeys".apikeyid;

--
-- Name: AppSettings; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public."AppSettings" (
    appsettingsid integer NOT NULL,
    selfserviceuser boolean DEFAULT false,
    downloadenabled boolean DEFAULT true,
    newsfeedsubscribed boolean DEFAULT false,
    downloadfoldercover boolean DEFAULT false,
    downloadepisodecover boolean DEFAULT false,
    downloadmetadatasidecar boolean DEFAULT false,
    downloadmetadataformat character varying(20) DEFAULT 'both'::character varying,
    downloadmetadatasubfolder boolean DEFAULT true,
    podpingenabled boolean DEFAULT false NOT NULL,
    encryptionkey text,
    ytdlpautoupdate boolean DEFAULT true,
    ytdlpchannel character varying(20) DEFAULT 'stable'::character varying,
    ytdlplastupdated timestamp without time zone,
    ytdlplastresult text
);

--
-- Name: AppSettings_appsettingsid_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public."AppSettings_appsettingsid_seq"
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;

--
-- Name: AppSettings_appsettingsid_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public."AppSettings_appsettingsid_seq" OWNED BY public."AppSettings".appsettingsid;

--
-- Name: CollectionEpisodes; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public."CollectionEpisodes" (
    collectionepisodeid integer NOT NULL,
    collectionid integer NOT NULL,
    episodeid integer,
    videoid integer,
    addedat timestamp without time zone DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT "CollectionEpisodes_check" CHECK ((((episodeid IS NOT NULL) AND (videoid IS NULL)) OR ((episodeid IS NULL) AND (videoid IS NOT NULL))))
);

--
-- Name: CollectionEpisodes_collectionepisodeid_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public."CollectionEpisodes_collectionepisodeid_seq"
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;

--
-- Name: CollectionEpisodes_collectionepisodeid_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public."CollectionEpisodes_collectionepisodeid_seq" OWNED BY public."CollectionEpisodes".collectionepisodeid;

--
-- Name: Collections; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public."Collections" (
    collectionid integer NOT NULL,
    userid integer NOT NULL,
    name character varying(255) NOT NULL,
    description text,
    isdefault boolean DEFAULT false NOT NULL,
    icon character varying(50) DEFAULT 'ph-bookmark-simple'::character varying NOT NULL,
    createdat timestamp without time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    lastupdated timestamp without time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    autoaddcategories text
);

--
-- Name: Collections_collectionid_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public."Collections_collectionid_seq"
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;

--
-- Name: Collections_collectionid_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public."Collections_collectionid_seq" OWNED BY public."Collections".collectionid;

--
-- Name: CustomThemes; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public."CustomThemes" (
    themeid integer NOT NULL,
    userid integer NOT NULL,
    name character varying(255) NOT NULL,
    background_color character varying(7) DEFAULT '#3C4252'::character varying NOT NULL,
    button_color character varying(7) DEFAULT '#3e4555'::character varying NOT NULL,
    container_button_color character varying(7) DEFAULT 'transparent'::character varying NOT NULL,
    button_text_color character varying(7) DEFAULT '#f6f5f4'::character varying NOT NULL,
    text_color character varying(7) DEFAULT '#f6f5f4'::character varying NOT NULL,
    text_secondary_color character varying(7) DEFAULT '#f6f5f4'::character varying NOT NULL,
    border_color character varying(7) DEFAULT '#000000'::character varying NOT NULL,
    accent_color character varying(7) DEFAULT '#6d747f'::character varying NOT NULL,
    prog_bar_color character varying(7) DEFAULT '#3550af'::character varying NOT NULL,
    error_color character varying(7) DEFAULT '#ff0000'::character varying NOT NULL,
    bonus_color character varying(7) DEFAULT '#000000'::character varying NOT NULL,
    secondary_background character varying(7) DEFAULT '#2e3440'::character varying NOT NULL,
    container_background character varying(7) DEFAULT '#2b2f3a'::character varying NOT NULL,
    standout_color character varying(7) DEFAULT '#6e8e92'::character varying NOT NULL,
    hover_color character varying(7) DEFAULT '#5d80aa'::character varying NOT NULL,
    link_color character varying(7) DEFAULT '#5d80aa'::character varying NOT NULL,
    thumb_color character varying(7) DEFAULT '#3550af'::character varying NOT NULL,
    unfilled_color character varying(7) DEFAULT '#d4d6d7'::character varying NOT NULL,
    check_box_color character varying(7) DEFAULT '#ffffff'::character varying NOT NULL
);

--
-- Name: CustomThemes_themeid_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public."CustomThemes_themeid_seq"
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;

--
-- Name: CustomThemes_themeid_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public."CustomThemes_themeid_seq" OWNED BY public."CustomThemes".themeid;

--
-- Name: DownloadedEpisodes; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public."DownloadedEpisodes" (
    downloadid integer NOT NULL,
    userid integer,
    episodeid integer,
    downloadeddate timestamp without time zone DEFAULT CURRENT_TIMESTAMP,
    downloadedsize bigint,
    downloadedlocation text,
    audiofingerprint character varying(64)
);

--
-- Name: DownloadedEpisodes_downloadid_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public."DownloadedEpisodes_downloadid_seq"
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;

--
-- Name: DownloadedEpisodes_downloadid_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public."DownloadedEpisodes_downloadid_seq" OWNED BY public."DownloadedEpisodes".downloadid;

--
-- Name: DownloadedVideos; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public."DownloadedVideos" (
    downloadid integer NOT NULL,
    userid integer,
    videoid integer,
    downloadeddate timestamp without time zone DEFAULT CURRENT_TIMESTAMP,
    downloadedsize bigint,
    downloadedlocation text
);

--
-- Name: DownloadedVideos_downloadid_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public."DownloadedVideos_downloadid_seq"
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;

--
-- Name: DownloadedVideos_downloadid_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public."DownloadedVideos_downloadid_seq" OWNED BY public."DownloadedVideos".downloadid;

--
-- Name: EmailSettings; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public."EmailSettings" (
    emailsettingsid integer NOT NULL,
    server_name character varying(255),
    server_port integer,
    from_email character varying(255),
    send_mode character varying(255),
    encryption character varying(255),
    auth_required boolean,
    username character varying(255),
    password character varying(255)
);

--
-- Name: EmailSettings_emailsettingsid_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public."EmailSettings_emailsettingsid_seq"
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;

--
-- Name: EmailSettings_emailsettingsid_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public."EmailSettings_emailsettingsid_seq" OWNED BY public."EmailSettings".emailsettingsid;

--
-- Name: EpisodeAdSkipReview; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public."EpisodeAdSkipReview" (
    reviewid integer NOT NULL,
    userid integer NOT NULL,
    segmentid integer NOT NULL,
    status character varying(20) NOT NULL,
    createdat timestamp without time zone DEFAULT CURRENT_TIMESTAMP NOT NULL
);

--
-- Name: EpisodeAdSkipReview_reviewid_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public."EpisodeAdSkipReview_reviewid_seq"
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;

--
-- Name: EpisodeAdSkipReview_reviewid_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public."EpisodeAdSkipReview_reviewid_seq" OWNED BY public."EpisodeAdSkipReview".reviewid;

--
-- Name: EpisodeIDAliases; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public."EpisodeIDAliases" (
    oldepisodeid integer NOT NULL,
    episodeid integer NOT NULL,
    createdat timestamp without time zone DEFAULT CURRENT_TIMESTAMP NOT NULL
);

--
-- Name: EpisodePeople; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public."EpisodePeople" (
    episodeid integer NOT NULL,
    personid integer NOT NULL,
    role character varying(64) NOT NULL,
    persongroup character varying(64),
    source character varying(16) NOT NULL,
    verified boolean DEFAULT true NOT NULL
);

--
-- Name: EpisodeQueue; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public."EpisodeQueue" (
    queueid integer NOT NULL,
    queuedate timestamp without time zone DEFAULT CURRENT_TIMESTAMP,
    userid integer,
    episodeid integer,
    queueposition integer DEFAULT 0 NOT NULL,
    is_youtube boolean DEFAULT false
);

--
-- Name: EpisodeQueue_queueid_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public."EpisodeQueue_queueid_seq"
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;

--
-- Name: EpisodeQueue_queueid_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public."EpisodeQueue_queueid_seq" OWNED BY public."EpisodeQueue".queueid;

--
-- Name: EpisodeSkipSegments; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public."EpisodeSkipSegments" (
    segmentid integer NOT NULL,
    episodeid integer,
    videoid integer,
    kind character varying(20) NOT NULL,
    starttime double precision NOT NULL,
    endtime double precision NOT NULL,
    source character varying(30) NOT NULL,
    createdat timestamp without time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    CONSTRAINT "EpisodeSkipSegments_check" CHECK ((((episodeid IS NOT NULL) AND (videoid IS NULL)) OR ((episodeid IS NULL) AND (videoid IS NOT NULL))))
);

--
-- Name: EpisodeSkipSegments_segmentid_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public."EpisodeSkipSegments_segmentid_seq"
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;

--
-- Name: EpisodeSkipSegments_segmentid_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public."EpisodeSkipSegments_segmentid_seq" OWNED BY public."EpisodeSkipSegments".segmentid;

--
-- Name: EpisodeTranscripts; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public."EpisodeTranscripts" (
    transcriptid integer NOT NULL,
    episodeid integer,
    videoid integer,
    source character varying(20) DEFAULT 'generated'::character varying NOT NULL,
    language character varying(20),
    model character varying(100),
    transcripttext text,
    segments jsonb,
    status character varying(20) DEFAULT 'complete'::character varying NOT NULL,
    createdat timestamp without time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    audiofingerprint character varying(64),
    audioduration double precision,
    audiosource character varying(16),
    CONSTRAINT "EpisodeTranscripts_check" CHECK ((((episodeid IS NOT NULL) AND (videoid IS NULL)) OR ((episodeid IS NULL) AND (videoid IS NOT NULL))))
);

--
-- Name: EpisodeTranscripts_transcriptid_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public."EpisodeTranscripts_transcriptid_seq"
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;

--
-- Name: EpisodeTranscripts_transcriptid_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public."EpisodeTranscripts_transcriptid_seq" OWNED BY public."EpisodeTranscripts".transcriptid;

--
-- Name: Episodes; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public."Episodes" (
    episodeid integer NOT NULL,
    podcastid integer,
    episodetitle text,
    episodedescription text,
    episodeurl text,
    episodeartwork text,
    episodepubdate timestamp without time zone,
    episodeduration integer,
    completed boolean DEFAULT false,
    is_video boolean DEFAULT false,
    episodeguid text,
    silencedetected boolean DEFAULT false,
    adsdetected boolean DEFAULT false,
    chaptersurl text,
    transcriptsjson text,
    feedid integer
);

--
-- Name: Episodes_episodeid_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public."Episodes_episodeid_seq"
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;

--
-- Name: Episodes_episodeid_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public."Episodes_episodeid_seq" OWNED BY public."Episodes".episodeid;

--
-- Name: Feeds; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public."Feeds" (
    feedid integer NOT NULL,
    feedurl text NOT NULL,
    feedurlhash character(64) NOT NULL,
    credentialkey character varying(64) DEFAULT ''::character varying NOT NULL,
    isyoutubechannel boolean DEFAULT false NOT NULL,
    feedetag text,
    feedlastmodified text,
    feedcontenthash text,
    refreshnotbefore timestamp without time zone,
    nextrefreshat timestamp without time zone DEFAULT (CURRENT_TIMESTAMP + '00:05:00'::interval),
    refreshintervalminutes integer,
    lastrefreshattempt timestamp without time zone,
    lastrefreshsuccess timestamp without time zone,
    consecutivefailures integer DEFAULT 0 NOT NULL,
    lasterrormessage text,
    failingsince timestamp without time zone,
    lasterrorkind character varying(32),
    createdat timestamp without time zone DEFAULT CURRENT_TIMESTAMP NOT NULL
);

--
-- Name: Feeds_feedid_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public."Feeds_feedid_seq"
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;

--
-- Name: Feeds_feedid_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public."Feeds_feedid_seq" OWNED BY public."Feeds".feedid;

--
-- Name: GpodderAppPasswords; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public."GpodderAppPasswords" (
    apppasswordid integer NOT NULL,
    userid integer NOT NULL,
    label character varying(255) NOT NULL,
    passwordhash character varying(500) NOT NULL,
    createdat timestamp without time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    lastusedat timestamp without time zone
);

--
-- Name: GpodderAppPasswords_apppasswordid_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public."GpodderAppPasswords_apppasswordid_seq"
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;

--
-- Name: GpodderAppPasswords_apppasswordid_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public."GpodderAppPasswords_apppasswordid_seq" OWNED BY public."GpodderAppPasswords".apppasswordid;

--
-- Name: GpodderDeviceSubscriptions; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public."GpodderDeviceSubscriptions" (
    deviceid integer NOT NULL,
    podcasturl text NOT NULL
);

--
-- Name: GpodderDevices; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public."GpodderDevices" (
    deviceid integer NOT NULL,
    userid integer NOT NULL,
    devicename character varying(255) NOT NULL,
    devicetype character varying(50) DEFAULT 'desktop'::character varying,
    devicecaption character varying(255),
    usercaption character varying(255),
    isdefault boolean DEFAULT false,
    lastsync timestamp without time zone DEFAULT CURRENT_TIMESTAMP,
    isactive boolean DEFAULT true,
    systemrole character varying(16),
    subsdownloadcursor bigint
);

--
-- Name: GpodderDevices_deviceid_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public."GpodderDevices_deviceid_seq"
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;

--
-- Name: GpodderDevices_deviceid_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public."GpodderDevices_deviceid_seq" OWNED BY public."GpodderDevices".deviceid;

--
-- Name: GpodderSessions; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public."GpodderSessions" (
    sessionid integer NOT NULL,
    userid integer NOT NULL,
    sessiontoken text NOT NULL,
    createdat timestamp without time zone DEFAULT CURRENT_TIMESTAMP,
    expiresat timestamp without time zone NOT NULL,
    lastactive timestamp without time zone DEFAULT CURRENT_TIMESTAMP,
    useragent text,
    clientip text,
    episodesdownloadcursor bigint,
    apppasswordid integer
);

--
-- Name: GpodderSessions_sessionid_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public."GpodderSessions_sessionid_seq"
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;

--
-- Name: GpodderSessions_sessionid_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public."GpodderSessions_sessionid_seq" OWNED BY public."GpodderSessions".sessionid;

--
-- Name: GpodderSubscriptionSnapshot; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public."GpodderSubscriptionSnapshot" (
    snapshotid integer NOT NULL,
    userid integer NOT NULL,
    synctarget text NOT NULL,
    feedurl text NOT NULL
);

--
-- Name: GpodderSubscriptionSnapshot_snapshotid_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public."GpodderSubscriptionSnapshot_snapshotid_seq"
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;

--
-- Name: GpodderSubscriptionSnapshot_snapshotid_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public."GpodderSubscriptionSnapshot_snapshotid_seq" OWNED BY public."GpodderSubscriptionSnapshot".snapshotid;

--
-- Name: GpodderSyncDevicePairs; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public."GpodderSyncDevicePairs" (
    pairid integer NOT NULL,
    userid integer NOT NULL,
    deviceid1 integer NOT NULL,
    deviceid2 integer NOT NULL,
    createdat timestamp without time zone DEFAULT CURRENT_TIMESTAMP
);

--
-- Name: GpodderSyncDevicePairs_pairid_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public."GpodderSyncDevicePairs_pairid_seq"
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;

--
-- Name: GpodderSyncDevicePairs_pairid_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public."GpodderSyncDevicePairs_pairid_seq" OWNED BY public."GpodderSyncDevicePairs".pairid;

--
-- Name: GpodderSyncDeviceState; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public."GpodderSyncDeviceState" (
    devicestateid integer NOT NULL,
    userid integer NOT NULL,
    deviceid integer NOT NULL,
    subscriptioncount integer DEFAULT 0,
    lastupdated timestamp without time zone DEFAULT CURRENT_TIMESTAMP
);

--
-- Name: GpodderSyncDeviceState_devicestateid_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public."GpodderSyncDeviceState_devicestateid_seq"
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;

--
-- Name: GpodderSyncDeviceState_devicestateid_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public."GpodderSyncDeviceState_devicestateid_seq" OWNED BY public."GpodderSyncDeviceState".devicestateid;

--
-- Name: GpodderSyncEpisodeActions; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public."GpodderSyncEpisodeActions" (
    actionid integer NOT NULL,
    userid integer NOT NULL,
    deviceid integer,
    podcasturl text NOT NULL,
    episodeurl text NOT NULL,
    action character varying(20) NOT NULL,
    "timestamp" bigint NOT NULL,
    started integer,
    "position" integer,
    total integer,
    serverts bigint NOT NULL,
    guid text,
    episodeid integer,
    origin character varying(32) DEFAULT 'client'::character varying NOT NULL
);

--
-- Name: GpodderSyncEpisodeActions_actionid_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public."GpodderSyncEpisodeActions_actionid_seq"
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;

--
-- Name: GpodderSyncEpisodeActions_actionid_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public."GpodderSyncEpisodeActions_actionid_seq" OWNED BY public."GpodderSyncEpisodeActions".actionid;

--
-- Name: GpodderSyncMigrations; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public."GpodderSyncMigrations" (
    version integer NOT NULL,
    description text NOT NULL,
    appliedat timestamp without time zone DEFAULT CURRENT_TIMESTAMP NOT NULL
);

--
-- Name: GpodderSyncPodcastListEntries; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public."GpodderSyncPodcastListEntries" (
    entryid integer NOT NULL,
    listid integer NOT NULL,
    podcasturl text NOT NULL,
    createdat timestamp without time zone DEFAULT CURRENT_TIMESTAMP
);

--
-- Name: GpodderSyncPodcastListEntries_entryid_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public."GpodderSyncPodcastListEntries_entryid_seq"
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;

--
-- Name: GpodderSyncPodcastListEntries_entryid_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public."GpodderSyncPodcastListEntries_entryid_seq" OWNED BY public."GpodderSyncPodcastListEntries".entryid;

--
-- Name: GpodderSyncPodcastLists; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public."GpodderSyncPodcastLists" (
    listid integer NOT NULL,
    userid integer NOT NULL,
    name character varying(255) NOT NULL,
    title character varying(255) NOT NULL,
    createdat timestamp without time zone DEFAULT CURRENT_TIMESTAMP
);

--
-- Name: GpodderSyncPodcastLists_listid_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public."GpodderSyncPodcastLists_listid_seq"
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;

--
-- Name: GpodderSyncPodcastLists_listid_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public."GpodderSyncPodcastLists_listid_seq" OWNED BY public."GpodderSyncPodcastLists".listid;

--
-- Name: GpodderSyncSettings; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public."GpodderSyncSettings" (
    settingid integer NOT NULL,
    userid integer NOT NULL,
    scope character varying(20) NOT NULL,
    deviceid integer,
    podcasturl text,
    episodeurl text,
    settingkey character varying(255) NOT NULL,
    settingvalue text,
    createdat timestamp without time zone DEFAULT CURRENT_TIMESTAMP,
    lastupdated timestamp without time zone DEFAULT CURRENT_TIMESTAMP,
    apiversion character varying(10) DEFAULT '2.0'::character varying
);

--
-- Name: GpodderSyncSettings_settingid_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public."GpodderSyncSettings_settingid_seq"
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;

--
-- Name: GpodderSyncSettings_settingid_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public."GpodderSyncSettings_settingid_seq" OWNED BY public."GpodderSyncSettings".settingid;

--
-- Name: GpodderSyncState; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public."GpodderSyncState" (
    syncstateid integer NOT NULL,
    userid integer NOT NULL,
    deviceid integer NOT NULL,
    lasttimestamp bigint DEFAULT 0,
    episodestimestamp bigint DEFAULT 0
);

--
-- Name: GpodderSyncState_syncstateid_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public."GpodderSyncState_syncstateid_seq"
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;

--
-- Name: GpodderSyncState_syncstateid_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public."GpodderSyncState_syncstateid_seq" OWNED BY public."GpodderSyncState".syncstateid;

--
-- Name: GpodderSyncSubscriptions; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public."GpodderSyncSubscriptions" (
    subscriptionid integer NOT NULL,
    userid integer NOT NULL,
    deviceid integer,
    podcasturl text NOT NULL,
    action character varying(10) NOT NULL,
    "timestamp" bigint NOT NULL,
    serverts bigint NOT NULL,
    origin character varying(32) DEFAULT 'client'::character varying NOT NULL
);

--
-- Name: GpodderSyncSubscriptions_subscriptionid_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public."GpodderSyncSubscriptions_subscriptionid_seq"
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;

--
-- Name: GpodderSyncSubscriptions_subscriptionid_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public."GpodderSyncSubscriptions_subscriptionid_seq" OWNED BY public."GpodderSyncSubscriptions".subscriptionid;

--
-- Name: InAppNotifications; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public."InAppNotifications" (
    notificationid character varying(64) NOT NULL,
    userid integer NOT NULL,
    payload text NOT NULL,
    isread boolean DEFAULT false NOT NULL,
    createdat timestamp without time zone NOT NULL,
    expiresat timestamp without time zone NOT NULL
);

--
-- Name: OIDCProviders; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public."OIDCProviders" (
    providerid integer NOT NULL,
    providername character varying(255) NOT NULL,
    clientid character varying(255) NOT NULL,
    clientsecret character varying(500) NOT NULL,
    authorizationurl character varying(255) NOT NULL,
    tokenurl character varying(255) NOT NULL,
    userinfourl character varying(255) NOT NULL,
    scope character varying(255) DEFAULT 'openid email profile'::character varying,
    buttoncolor character varying(50) DEFAULT '#000000'::character varying,
    buttontext character varying(255) NOT NULL,
    buttontextcolor character varying(50) DEFAULT '#000000'::character varying,
    iconsvg text,
    enabled boolean DEFAULT true,
    created timestamp without time zone DEFAULT CURRENT_TIMESTAMP,
    modified timestamp without time zone DEFAULT CURRENT_TIMESTAMP,
    nameclaim character varying(255),
    emailclaim character varying(255),
    usernameclaim character varying(255),
    rolesclaim character varying(255),
    userrole character varying(255),
    adminrole character varying(255),
    initializedfromenv boolean DEFAULT false
);

--
-- Name: COLUMN "OIDCProviders".initializedfromenv; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public."OIDCProviders".initializedfromenv IS 'Indicates if this provider was created from environment variables and should not be removable via UI';

--
-- Name: OIDCProviders_providerid_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public."OIDCProviders_providerid_seq"
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;

--
-- Name: OIDCProviders_providerid_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public."OIDCProviders_providerid_seq" OWNED BY public."OIDCProviders".providerid;

--
-- Name: PersonExternalEpisodes; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public."PersonExternalEpisodes" (
    id integer NOT NULL,
    personid integer NOT NULL,
    feedurl text NOT NULL,
    podcasttitle text,
    podcastartwork text,
    podcastindexid integer,
    episodeguid text,
    episodetitle text NOT NULL,
    episodedescription text,
    episodeurl text NOT NULL,
    episodeartwork text,
    episodepubdate timestamp without time zone,
    episodeduration integer,
    role character varying(64),
    source character varying(16) NOT NULL,
    fetchedat timestamp without time zone DEFAULT CURRENT_TIMESTAMP
);

--
-- Name: PersonExternalEpisodes_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public."PersonExternalEpisodes_id_seq"
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;

--
-- Name: PersonExternalEpisodes_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public."PersonExternalEpisodes_id_seq" OWNED BY public."PersonExternalEpisodes".id;

--
-- Name: PersonFollows; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public."PersonFollows" (
    userid integer NOT NULL,
    personid integer NOT NULL,
    createdat timestamp without time zone DEFAULT CURRENT_TIMESTAMP
);

--
-- Name: Persons; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public."Persons" (
    personid integer NOT NULL,
    name text NOT NULL,
    namenormalized text NOT NULL,
    img text,
    href text,
    podpeopleid integer,
    externalrefreshedat timestamp without time zone,
    createdat timestamp without time zone DEFAULT CURRENT_TIMESTAMP
);

--
-- Name: Persons_personid_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public."Persons_personid_seq"
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;

--
-- Name: Persons_personid_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public."Persons_personid_seq" OWNED BY public."Persons".personid;

--
-- Name: PlaylistContents; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public."PlaylistContents" (
    playlistcontentid integer NOT NULL,
    playlistid integer,
    episodeid integer,
    videoid integer,
    "position" integer,
    dateadded timestamp without time zone DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT "PlaylistContents_check" CHECK ((((episodeid IS NOT NULL) AND (videoid IS NULL)) OR ((episodeid IS NULL) AND (videoid IS NOT NULL))))
);

--
-- Name: PlaylistContents_playlistcontentid_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public."PlaylistContents_playlistcontentid_seq"
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;

--
-- Name: PlaylistContents_playlistcontentid_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public."PlaylistContents_playlistcontentid_seq" OWNED BY public."PlaylistContents".playlistcontentid;

--
-- Name: Playlists; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public."Playlists" (
    playlistid integer NOT NULL,
    userid integer NOT NULL,
    name character varying(255) NOT NULL,
    description text,
    issystemplaylist boolean DEFAULT false NOT NULL,
    podcastids integer[],
    includeunplayed boolean DEFAULT true NOT NULL,
    includepartiallyplayed boolean DEFAULT true NOT NULL,
    includeplayed boolean DEFAULT false NOT NULL,
    minduration integer,
    maxduration integer,
    sortorder character varying(50) DEFAULT 'date_desc'::character varying NOT NULL,
    groupbypodcast boolean DEFAULT false NOT NULL,
    maxepisodes integer,
    playprogressmin double precision,
    playprogressmax double precision,
    timefilterhours integer,
    lastupdated timestamp without time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    created timestamp without time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    iconname character varying(50) DEFAULT 'ph-playlist'::character varying NOT NULL,
    episodecount integer DEFAULT 0,
    CONSTRAINT "Playlists_check" CHECK (((playprogressmin IS NULL) OR (playprogressmax IS NULL) OR (playprogressmin <= playprogressmax))),
    CONSTRAINT "Playlists_maxduration_check" CHECK (((maxduration IS NULL) OR (maxduration >= 0))),
    CONSTRAINT "Playlists_minduration_check" CHECK (((minduration IS NULL) OR (minduration >= 0))),
    CONSTRAINT "Playlists_playprogressmax_check" CHECK (((playprogressmax IS NULL) OR ((playprogressmax >= (0)::double precision) AND (playprogressmax <= (100)::double precision)))),
    CONSTRAINT "Playlists_playprogressmin_check" CHECK (((playprogressmin IS NULL) OR ((playprogressmin >= (0)::double precision) AND (playprogressmin <= (100)::double precision)))),
    CONSTRAINT "Playlists_sortorder_check" CHECK (((sortorder)::text = ANY ((ARRAY['date_asc'::character varying, 'date_desc'::character varying, 'duration_asc'::character varying, 'duration_desc'::character varying, 'listen_progress'::character varying, 'completion'::character varying])::text[])))
);

--
-- Name: Playlists_playlistid_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public."Playlists_playlistid_seq"
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;

--
-- Name: Playlists_playlistid_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public."Playlists_playlistid_seq" OWNED BY public."Playlists".playlistid;

--
-- Name: PodcastFeedAliases; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public."PodcastFeedAliases" (
    aliasid integer NOT NULL,
    podcastid integer NOT NULL,
    userid integer NOT NULL,
    feedurl text NOT NULL,
    createdat timestamp without time zone DEFAULT CURRENT_TIMESTAMP NOT NULL
);

--
-- Name: PodcastFeedAliases_aliasid_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public."PodcastFeedAliases_aliasid_seq"
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;

--
-- Name: PodcastFeedAliases_aliasid_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public."PodcastFeedAliases_aliasid_seq" OWNED BY public."PodcastFeedAliases".aliasid;

--
-- Name: PodcastPeople; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public."PodcastPeople" (
    podcastid integer NOT NULL,
    personid integer NOT NULL,
    role character varying(64) NOT NULL,
    persongroup character varying(64),
    source character varying(16) NOT NULL,
    verified boolean DEFAULT true NOT NULL
);

--
-- Name: Podcasts; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public."Podcasts" (
    podcastid integer NOT NULL,
    podcastindexid integer,
    podcastname text,
    artworkurl text,
    author text,
    categories text,
    description text,
    episodecount integer,
    feedurl text,
    websiteurl text,
    explicit boolean,
    userid integer,
    autodownload boolean DEFAULT false,
    autoqueue boolean DEFAULT false,
    startskip integer DEFAULT 0,
    endskip integer DEFAULT 0,
    username text,
    password text,
    isyoutubechannel boolean DEFAULT false,
    notificationsenabled boolean DEFAULT false,
    feedcutoffdays integer DEFAULT 0,
    playbackspeed numeric(2,1) DEFAULT 1.0,
    playbackspeedcustomized boolean DEFAULT false,
    autodownloaddeletedays integer DEFAULT 0,
    autodownloaddeletecustomized boolean DEFAULT false,
    feedcontenthash text,
    refreshnotbefore timestamp without time zone,
    failingsince timestamp without time zone,
    lasterrorkind character varying(32),
    problemnotified boolean DEFAULT false NOT NULL,
    nextrefreshat timestamp without time zone DEFAULT (CURRENT_TIMESTAMP + '00:05:00'::interval),
    refreshintervalminutes integer,
    editedmetadata character varying(255),
    ignorepodcastindex boolean DEFAULT false,
    displaypodcast boolean DEFAULT true,
    refreshpodcast boolean DEFAULT true,
    mergedpodcastids text,
    usepodcastcovers boolean DEFAULT false,
    usepodcastcoverscustomized boolean DEFAULT false,
    autoplaynext boolean DEFAULT false,
    isfavorite boolean DEFAULT false,
    feedetag text,
    feedlastmodified text,
    lastrefreshattempt timestamp without time zone,
    lastrefreshsuccess timestamp without time zone,
    consecutivefailures integer DEFAULT 0,
    lasterrormessage text,
    trimsilence boolean DEFAULT false,
    silencethreshold integer DEFAULT 2,
    autotranscribe boolean DEFAULT false,
    autoaddetect boolean DEFAULT false,
    adskipautoactivate boolean DEFAULT true,
    podcasting2data text,
    podcasting2hash character varying(32),
    podcastguid character varying(255),
    videominminutes integer,
    videomaxminutes integer,
    videotitlefilter character varying(255),
    autodeleteoncomplete boolean,
    feedid integer
);

--
-- Name: Podcasts_podcastid_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public."Podcasts_podcastid_seq"
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;

--
-- Name: Podcasts_podcastid_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public."Podcasts_podcastid_seq" OWNED BY public."Podcasts".podcastid;

--
-- Name: RecommendationCache; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public."RecommendationCache" (
    userid integer NOT NULL,
    generatedat timestamp without time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    resultsjson text NOT NULL
);

--
-- Name: RssKeyMap; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public."RssKeyMap" (
    rsskeyid integer,
    podcastid integer
);

--
-- Name: RssKeys; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public."RssKeys" (
    rsskeyid integer NOT NULL,
    userid integer,
    rsskey text,
    created timestamp without time zone DEFAULT CURRENT_TIMESTAMP
);

--
-- Name: RssKeys_rsskeyid_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public."RssKeys_rsskeyid_seq"
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;

--
-- Name: RssKeys_rsskeyid_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public."RssKeys_rsskeyid_seq" OWNED BY public."RssKeys".rsskeyid;

--
-- Name: SavedEpisodes; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public."SavedEpisodes" (
    saveid integer NOT NULL,
    userid integer,
    episodeid integer,
    savedate timestamp without time zone DEFAULT CURRENT_TIMESTAMP
);

--
-- Name: SavedEpisodes_saveid_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public."SavedEpisodes_saveid_seq"
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;

--
-- Name: SavedEpisodes_saveid_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public."SavedEpisodes_saveid_seq" OWNED BY public."SavedEpisodes".saveid;

--
-- Name: SavedVideos; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public."SavedVideos" (
    saveid integer NOT NULL,
    userid integer,
    videoid integer,
    savedate timestamp without time zone DEFAULT CURRENT_TIMESTAMP
);

--
-- Name: SavedVideos_saveid_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public."SavedVideos_saveid_seq"
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;

--
-- Name: SavedVideos_saveid_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public."SavedVideos_saveid_seq" OWNED BY public."SavedVideos".saveid;

--
-- Name: ScheduledBackups; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public."ScheduledBackups" (
    id integer NOT NULL,
    userid integer NOT NULL,
    cron_schedule character varying(50) NOT NULL,
    enabled boolean DEFAULT false NOT NULL,
    created_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP,
    updated_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP,
    retention_count integer,
    last_run timestamp without time zone
);

--
-- Name: ScheduledBackups_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public."ScheduledBackups_id_seq"
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;

--
-- Name: ScheduledBackups_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public."ScheduledBackups_id_seq" OWNED BY public."ScheduledBackups".id;

--
-- Name: Sessions; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public."Sessions" (
    sessionid integer NOT NULL,
    userid integer NOT NULL,
    sessiontoken text NOT NULL,
    expirationtime timestamp without time zone NOT NULL,
    isactive boolean DEFAULT true
);

--
-- Name: Sessions_sessionid_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public."Sessions_sessionid_seq"
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;

--
-- Name: Sessions_sessionid_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public."Sessions_sessionid_seq" OWNED BY public."Sessions".sessionid;

--
-- Name: SharedEpisodes; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public."SharedEpisodes" (
    sharedepisodeid integer NOT NULL,
    episodeid integer NOT NULL,
    sharedby integer NOT NULL,
    sharedwith integer,
    sharecode text,
    expirationdate timestamp without time zone
);

--
-- Name: SharedEpisodes_sharedepisodeid_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public."SharedEpisodes_sharedepisodeid_seq"
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;

--
-- Name: SharedEpisodes_sharedepisodeid_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public."SharedEpisodes_sharedepisodeid_seq" OWNED BY public."SharedEpisodes".sharedepisodeid;

--
-- Name: SyncImportFailures; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public."SyncImportFailures" (
    failureid integer NOT NULL,
    userid integer NOT NULL,
    feedurl text NOT NULL,
    origin character varying(32) NOT NULL,
    errorkind character varying(32) NOT NULL,
    lasterror text,
    attempts integer DEFAULT 1 NOT NULL,
    firstfailedat timestamp without time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    lastattemptat timestamp without time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    nextattemptat timestamp without time zone
);

--
-- Name: SyncImportFailures_failureid_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public."SyncImportFailures_failureid_seq"
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;

--
-- Name: SyncImportFailures_failureid_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public."SyncImportFailures_failureid_seq" OWNED BY public."SyncImportFailures".failureid;

--
-- Name: SyncTargets; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public."SyncTargets" (
    targetid integer NOT NULL,
    userid integer NOT NULL,
    kind character varying(16) NOT NULL,
    url text NOT NULL,
    username character varying(255) DEFAULT ''::character varying NOT NULL,
    encryptedsecret text NOT NULL,
    devicename character varying(255),
    enabled boolean DEFAULT true NOT NULL,
    subspullcursor bigint DEFAULT 0 NOT NULL,
    actionspullcursor bigint DEFAULT 0 NOT NULL,
    subspushcursor bigint DEFAULT 0 NOT NULL,
    actionspushcursor bigint DEFAULT 0 NOT NULL,
    needsfullsync boolean DEFAULT true NOT NULL,
    lastattemptat timestamp without time zone,
    lastsuccessat timestamp without time zone,
    lasterror text,
    consecutivefailures integer DEFAULT 0 NOT NULL,
    createdat timestamp without time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    CONSTRAINT "SyncTargets_kind_check" CHECK (((kind)::text = ANY ((ARRAY['gpodder'::character varying, 'nextcloud'::character varying])::text[])))
);

--
-- Name: SyncTargets_targetid_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public."SyncTargets_targetid_seq"
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;

--
-- Name: SyncTargets_targetid_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public."SyncTargets_targetid_seq" OWNED BY public."SyncTargets".targetid;

--
-- Name: UserEpisodeHistory; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public."UserEpisodeHistory" (
    userepisodehistoryid integer NOT NULL,
    userid integer,
    episodeid integer,
    listendate timestamp without time zone,
    listenduration integer
);

--
-- Name: UserEpisodeHistory_userepisodehistoryid_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public."UserEpisodeHistory_userepisodehistoryid_seq"
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;

--
-- Name: UserEpisodeHistory_userepisodehistoryid_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public."UserEpisodeHistory_userepisodehistoryid_seq" OWNED BY public."UserEpisodeHistory".userepisodehistoryid;

--
-- Name: UserEpisodeState; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public."UserEpisodeState" (
    userid integer NOT NULL,
    episodeid integer NOT NULL,
    completed boolean DEFAULT false NOT NULL,
    completedat timestamp without time zone
);

--
-- Name: UserNotificationSettings; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public."UserNotificationSettings" (
    settingid integer NOT NULL,
    userid integer,
    platform character varying(50) NOT NULL,
    enabled boolean DEFAULT true,
    ntfytopic character varying(255),
    ntfyserverurl character varying(255) DEFAULT 'https://ntfy.sh'::character varying,
    gotifyurl character varying(255),
    gotifytoken character varying(255),
    created_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP,
    updated_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP,
    ntfyusername character varying(255),
    ntfypassword character varying(255),
    ntfyaccesstoken character varying(255),
    httpurl character varying(500),
    httptoken character varying(255),
    httpmethod character varying(10) DEFAULT 'POST'::character varying
);

--
-- Name: UserNotificationSettings_settingid_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public."UserNotificationSettings_settingid_seq"
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;

--
-- Name: UserNotificationSettings_settingid_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public."UserNotificationSettings_settingid_seq" OWNED BY public."UserNotificationSettings".settingid;

--
-- Name: UserSettings; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public."UserSettings" (
    usersettingid integer NOT NULL,
    userid integer,
    theme character varying(255) DEFAULT 'Nordic'::character varying,
    startpage character varying(255) DEFAULT 'home'::character varying,
    autocompleteseconds integer DEFAULT 0,
    collection_add_ui character varying(10) DEFAULT 'modal'::character varying,
    queueaddposition character varying(10) DEFAULT 'bottom'::character varying NOT NULL
);

--
-- Name: UserSettings_usersettingid_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public."UserSettings_usersettingid_seq"
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;

--
-- Name: UserSettings_usersettingid_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public."UserSettings_usersettingid_seq" OWNED BY public."UserSettings".usersettingid;

--
-- Name: UserStats; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public."UserStats" (
    userstatsid integer NOT NULL,
    userid integer,
    usercreated timestamp without time zone DEFAULT CURRENT_TIMESTAMP,
    podcastsplayed integer DEFAULT 0,
    timelistened integer DEFAULT 0,
    podcastsadded integer DEFAULT 0,
    episodessaved integer DEFAULT 0,
    episodesdownloaded integer DEFAULT 0
);

--
-- Name: UserStats_userstatsid_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public."UserStats_userstatsid_seq"
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;

--
-- Name: UserStats_userstatsid_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public."UserStats_userstatsid_seq" OWNED BY public."UserStats".userstatsid;

--
-- Name: UserVideoHistory; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public."UserVideoHistory" (
    uservideohistoryid integer NOT NULL,
    userid integer,
    videoid integer,
    listendate timestamp without time zone,
    listenduration integer DEFAULT 0
);

--
-- Name: UserVideoHistory_uservideohistoryid_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public."UserVideoHistory_uservideohistoryid_seq"
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;

--
-- Name: UserVideoHistory_uservideohistoryid_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public."UserVideoHistory_uservideohistoryid_seq" OWNED BY public."UserVideoHistory".uservideohistoryid;

--
-- Name: Users; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public."Users" (
    userid integer NOT NULL,
    fullname character varying(255),
    username character varying(255),
    email character varying(255),
    hashed_pw character varying(500),
    isadmin boolean,
    reset_code text,
    reset_expiry timestamp without time zone,
    mfa_secret character varying(70),
    timezone character varying(50) DEFAULT 'UTC'::character varying,
    timeformat integer DEFAULT 24,
    dateformat character varying(3) DEFAULT 'ISO'::character varying,
    firstlogin boolean DEFAULT false,
    gpodderurl character varying(255) DEFAULT ''::character varying,
    pod_sync_type character varying(50) DEFAULT 'None'::character varying,
    gpodderloginname character varying(255) DEFAULT ''::character varying,
    gpoddertoken character varying(255) DEFAULT ''::character varying,
    enablerssfeeds boolean DEFAULT false,
    auth_type character varying(50) DEFAULT 'standard'::character varying,
    oidc_provider_id integer,
    oidc_subject character varying(255),
    playbackspeed numeric(2,1) DEFAULT 1.0,
    autodownloaddeletedays integer DEFAULT 0,
    defaultvolume integer DEFAULT 100,
    gpodderserverenabled boolean DEFAULT false NOT NULL,
    syncnotice character varying(64),
    lastsynctime timestamp with time zone,
    defaultgpodderdevice character varying(255),
    language character varying(10) DEFAULT 'en'::character varying,
    usepodcastcovers boolean DEFAULT false,
    autodeleteoncomplete boolean DEFAULT false,
    usegravatar boolean DEFAULT false NOT NULL
);

--
-- Name: COLUMN "Users".language; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public."Users".language IS 'ISO 639-1 language code for user interface language preference';

--
-- Name: Users_userid_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public."Users_userid_seq"
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;

--
-- Name: Users_userid_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public."Users_userid_seq" OWNED BY public."Users".userid;

--
-- Name: YouTubeVideos; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public."YouTubeVideos" (
    videoid integer NOT NULL,
    podcastid integer,
    videotitle text,
    videodescription text,
    videourl text,
    thumbnailurl text,
    publishedat timestamp without time zone,
    duration integer,
    youtubevideoid text,
    completed boolean DEFAULT false,
    listenposition integer DEFAULT 0
);

--
-- Name: YouTubeVideos_videoid_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public."YouTubeVideos_videoid_seq"
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;

--
-- Name: YouTubeVideos_videoid_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public."YouTubeVideos_videoid_seq" OWNED BY public."YouTubeVideos".videoid;

--
-- Name: AISettings aisettingsid; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public."AISettings" ALTER COLUMN aisettingsid SET DEFAULT nextval('public."AISettings_aisettingsid_seq"'::regclass);

--
-- Name: APIKeys apikeyid; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public."APIKeys" ALTER COLUMN apikeyid SET DEFAULT nextval('public."APIKeys_apikeyid_seq"'::regclass);

--
-- Name: AppSettings appsettingsid; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public."AppSettings" ALTER COLUMN appsettingsid SET DEFAULT nextval('public."AppSettings_appsettingsid_seq"'::regclass);

--
-- Name: CollectionEpisodes collectionepisodeid; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public."CollectionEpisodes" ALTER COLUMN collectionepisodeid SET DEFAULT nextval('public."CollectionEpisodes_collectionepisodeid_seq"'::regclass);

--
-- Name: Collections collectionid; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public."Collections" ALTER COLUMN collectionid SET DEFAULT nextval('public."Collections_collectionid_seq"'::regclass);

--
-- Name: CustomThemes themeid; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public."CustomThemes" ALTER COLUMN themeid SET DEFAULT nextval('public."CustomThemes_themeid_seq"'::regclass);

--
-- Name: DownloadedEpisodes downloadid; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public."DownloadedEpisodes" ALTER COLUMN downloadid SET DEFAULT nextval('public."DownloadedEpisodes_downloadid_seq"'::regclass);

--
-- Name: DownloadedVideos downloadid; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public."DownloadedVideos" ALTER COLUMN downloadid SET DEFAULT nextval('public."DownloadedVideos_downloadid_seq"'::regclass);

--
-- Name: EmailSettings emailsettingsid; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public."EmailSettings" ALTER COLUMN emailsettingsid SET DEFAULT nextval('public."EmailSettings_emailsettingsid_seq"'::regclass);

--
-- Name: EpisodeAdSkipReview reviewid; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public."EpisodeAdSkipReview" ALTER COLUMN reviewid SET DEFAULT nextval('public."EpisodeAdSkipReview_reviewid_seq"'::regclass);

--
-- Name: EpisodeQueue queueid; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public."EpisodeQueue" ALTER COLUMN queueid SET DEFAULT nextval('public."EpisodeQueue_queueid_seq"'::regclass);

--
-- Name: EpisodeSkipSegments segmentid; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public."EpisodeSkipSegments" ALTER COLUMN segmentid SET DEFAULT nextval('public."EpisodeSkipSegments_segmentid_seq"'::regclass);

--
-- Name: EpisodeTranscripts transcriptid; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public."EpisodeTranscripts" ALTER COLUMN transcriptid SET DEFAULT nextval('public."EpisodeTranscripts_transcriptid_seq"'::regclass);

--
-- Name: Episodes episodeid; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public."Episodes" ALTER COLUMN episodeid SET DEFAULT nextval('public."Episodes_episodeid_seq"'::regclass);

--
-- Name: Feeds feedid; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public."Feeds" ALTER COLUMN feedid SET DEFAULT nextval('public."Feeds_feedid_seq"'::regclass);

--
-- Name: GpodderAppPasswords apppasswordid; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public."GpodderAppPasswords" ALTER COLUMN apppasswordid SET DEFAULT nextval('public."GpodderAppPasswords_apppasswordid_seq"'::regclass);

--
-- Name: GpodderDevices deviceid; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public."GpodderDevices" ALTER COLUMN deviceid SET DEFAULT nextval('public."GpodderDevices_deviceid_seq"'::regclass);

--
-- Name: GpodderSessions sessionid; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public."GpodderSessions" ALTER COLUMN sessionid SET DEFAULT nextval('public."GpodderSessions_sessionid_seq"'::regclass);

--
-- Name: GpodderSubscriptionSnapshot snapshotid; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public."GpodderSubscriptionSnapshot" ALTER COLUMN snapshotid SET DEFAULT nextval('public."GpodderSubscriptionSnapshot_snapshotid_seq"'::regclass);

--
-- Name: GpodderSyncDevicePairs pairid; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public."GpodderSyncDevicePairs" ALTER COLUMN pairid SET DEFAULT nextval('public."GpodderSyncDevicePairs_pairid_seq"'::regclass);

--
-- Name: GpodderSyncDeviceState devicestateid; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public."GpodderSyncDeviceState" ALTER COLUMN devicestateid SET DEFAULT nextval('public."GpodderSyncDeviceState_devicestateid_seq"'::regclass);

--
-- Name: GpodderSyncEpisodeActions actionid; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public."GpodderSyncEpisodeActions" ALTER COLUMN actionid SET DEFAULT nextval('public."GpodderSyncEpisodeActions_actionid_seq"'::regclass);

--
-- Name: GpodderSyncPodcastListEntries entryid; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public."GpodderSyncPodcastListEntries" ALTER COLUMN entryid SET DEFAULT nextval('public."GpodderSyncPodcastListEntries_entryid_seq"'::regclass);

--
-- Name: GpodderSyncPodcastLists listid; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public."GpodderSyncPodcastLists" ALTER COLUMN listid SET DEFAULT nextval('public."GpodderSyncPodcastLists_listid_seq"'::regclass);

--
-- Name: GpodderSyncSettings settingid; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public."GpodderSyncSettings" ALTER COLUMN settingid SET DEFAULT nextval('public."GpodderSyncSettings_settingid_seq"'::regclass);

--
-- Name: GpodderSyncState syncstateid; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public."GpodderSyncState" ALTER COLUMN syncstateid SET DEFAULT nextval('public."GpodderSyncState_syncstateid_seq"'::regclass);

--
-- Name: GpodderSyncSubscriptions subscriptionid; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public."GpodderSyncSubscriptions" ALTER COLUMN subscriptionid SET DEFAULT nextval('public."GpodderSyncSubscriptions_subscriptionid_seq"'::regclass);

--
-- Name: OIDCProviders providerid; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public."OIDCProviders" ALTER COLUMN providerid SET DEFAULT nextval('public."OIDCProviders_providerid_seq"'::regclass);

--
-- Name: PersonExternalEpisodes id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public."PersonExternalEpisodes" ALTER COLUMN id SET DEFAULT nextval('public."PersonExternalEpisodes_id_seq"'::regclass);

--
-- Name: Persons personid; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public."Persons" ALTER COLUMN personid SET DEFAULT nextval('public."Persons_personid_seq"'::regclass);

--
-- Name: PlaylistContents playlistcontentid; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public."PlaylistContents" ALTER COLUMN playlistcontentid SET DEFAULT nextval('public."PlaylistContents_playlistcontentid_seq"'::regclass);

--
-- Name: Playlists playlistid; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public."Playlists" ALTER COLUMN playlistid SET DEFAULT nextval('public."Playlists_playlistid_seq"'::regclass);

--
-- Name: PodcastFeedAliases aliasid; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public."PodcastFeedAliases" ALTER COLUMN aliasid SET DEFAULT nextval('public."PodcastFeedAliases_aliasid_seq"'::regclass);

--
-- Name: Podcasts podcastid; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public."Podcasts" ALTER COLUMN podcastid SET DEFAULT nextval('public."Podcasts_podcastid_seq"'::regclass);

--
-- Name: RssKeys rsskeyid; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public."RssKeys" ALTER COLUMN rsskeyid SET DEFAULT nextval('public."RssKeys_rsskeyid_seq"'::regclass);

--
-- Name: SavedEpisodes saveid; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public."SavedEpisodes" ALTER COLUMN saveid SET DEFAULT nextval('public."SavedEpisodes_saveid_seq"'::regclass);

--
-- Name: SavedVideos saveid; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public."SavedVideos" ALTER COLUMN saveid SET DEFAULT nextval('public."SavedVideos_saveid_seq"'::regclass);

--
-- Name: ScheduledBackups id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public."ScheduledBackups" ALTER COLUMN id SET DEFAULT nextval('public."ScheduledBackups_id_seq"'::regclass);

--
-- Name: Sessions sessionid; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public."Sessions" ALTER COLUMN sessionid SET DEFAULT nextval('public."Sessions_sessionid_seq"'::regclass);

--
-- Name: SharedEpisodes sharedepisodeid; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public."SharedEpisodes" ALTER COLUMN sharedepisodeid SET DEFAULT nextval('public."SharedEpisodes_sharedepisodeid_seq"'::regclass);

--
-- Name: SyncImportFailures failureid; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public."SyncImportFailures" ALTER COLUMN failureid SET DEFAULT nextval('public."SyncImportFailures_failureid_seq"'::regclass);

--
-- Name: SyncTargets targetid; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public."SyncTargets" ALTER COLUMN targetid SET DEFAULT nextval('public."SyncTargets_targetid_seq"'::regclass);

--
-- Name: UserEpisodeHistory userepisodehistoryid; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public."UserEpisodeHistory" ALTER COLUMN userepisodehistoryid SET DEFAULT nextval('public."UserEpisodeHistory_userepisodehistoryid_seq"'::regclass);

--
-- Name: UserNotificationSettings settingid; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public."UserNotificationSettings" ALTER COLUMN settingid SET DEFAULT nextval('public."UserNotificationSettings_settingid_seq"'::regclass);

--
-- Name: UserSettings usersettingid; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public."UserSettings" ALTER COLUMN usersettingid SET DEFAULT nextval('public."UserSettings_usersettingid_seq"'::regclass);

--
-- Name: UserStats userstatsid; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public."UserStats" ALTER COLUMN userstatsid SET DEFAULT nextval('public."UserStats_userstatsid_seq"'::regclass);

--
-- Name: UserVideoHistory uservideohistoryid; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public."UserVideoHistory" ALTER COLUMN uservideohistoryid SET DEFAULT nextval('public."UserVideoHistory_uservideohistoryid_seq"'::regclass);

--
-- Name: Users userid; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public."Users" ALTER COLUMN userid SET DEFAULT nextval('public."Users_userid_seq"'::regclass);

--
-- Name: YouTubeVideos videoid; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public."YouTubeVideos" ALTER COLUMN videoid SET DEFAULT nextval('public."YouTubeVideos_videoid_seq"'::regclass);

--
-- Name: AISettings AISettings_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public."AISettings"
    ADD CONSTRAINT "AISettings_pkey" PRIMARY KEY (aisettingsid);

--
-- Name: APIKeys APIKeys_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public."APIKeys"
    ADD CONSTRAINT "APIKeys_pkey" PRIMARY KEY (apikeyid);

--
-- Name: AppSettings AppSettings_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public."AppSettings"
    ADD CONSTRAINT "AppSettings_pkey" PRIMARY KEY (appsettingsid);

--
-- Name: CollectionEpisodes CollectionEpisodes_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public."CollectionEpisodes"
    ADD CONSTRAINT "CollectionEpisodes_pkey" PRIMARY KEY (collectionepisodeid);

--
-- Name: Collections Collections_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public."Collections"
    ADD CONSTRAINT "Collections_pkey" PRIMARY KEY (collectionid);

--
-- Name: Collections Collections_userid_name_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public."Collections"
    ADD CONSTRAINT "Collections_userid_name_key" UNIQUE (userid, name);

--
-- Name: CustomThemes CustomThemes_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public."CustomThemes"
    ADD CONSTRAINT "CustomThemes_pkey" PRIMARY KEY (themeid);

--
-- Name: CustomThemes CustomThemes_userid_name_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public."CustomThemes"
    ADD CONSTRAINT "CustomThemes_userid_name_key" UNIQUE (userid, name);

--
-- Name: DownloadedEpisodes DownloadedEpisodes_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public."DownloadedEpisodes"
    ADD CONSTRAINT "DownloadedEpisodes_pkey" PRIMARY KEY (downloadid);

--
-- Name: DownloadedVideos DownloadedVideos_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public."DownloadedVideos"
    ADD CONSTRAINT "DownloadedVideos_pkey" PRIMARY KEY (downloadid);

--
-- Name: EmailSettings EmailSettings_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public."EmailSettings"
    ADD CONSTRAINT "EmailSettings_pkey" PRIMARY KEY (emailsettingsid);

--
-- Name: EpisodeAdSkipReview EpisodeAdSkipReview_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public."EpisodeAdSkipReview"
    ADD CONSTRAINT "EpisodeAdSkipReview_pkey" PRIMARY KEY (reviewid);

--
-- Name: EpisodeAdSkipReview EpisodeAdSkipReview_userid_segmentid_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public."EpisodeAdSkipReview"
    ADD CONSTRAINT "EpisodeAdSkipReview_userid_segmentid_key" UNIQUE (userid, segmentid);

--
-- Name: EpisodeIDAliases EpisodeIDAliases_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public."EpisodeIDAliases"
    ADD CONSTRAINT "EpisodeIDAliases_pkey" PRIMARY KEY (oldepisodeid);

--
-- Name: EpisodePeople EpisodePeople_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public."EpisodePeople"
    ADD CONSTRAINT "EpisodePeople_pkey" PRIMARY KEY (episodeid, personid, role, source);

--
-- Name: EpisodeQueue EpisodeQueue_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public."EpisodeQueue"
    ADD CONSTRAINT "EpisodeQueue_pkey" PRIMARY KEY (queueid);

--
-- Name: EpisodeSkipSegments EpisodeSkipSegments_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public."EpisodeSkipSegments"
    ADD CONSTRAINT "EpisodeSkipSegments_pkey" PRIMARY KEY (segmentid);

--
-- Name: EpisodeTranscripts EpisodeTranscripts_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public."EpisodeTranscripts"
    ADD CONSTRAINT "EpisodeTranscripts_pkey" PRIMARY KEY (transcriptid);

--
-- Name: Episodes Episodes_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public."Episodes"
    ADD CONSTRAINT "Episodes_pkey" PRIMARY KEY (episodeid);

--
-- Name: Feeds Feeds_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public."Feeds"
    ADD CONSTRAINT "Feeds_pkey" PRIMARY KEY (feedid);

--
-- Name: GpodderAppPasswords GpodderAppPasswords_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public."GpodderAppPasswords"
    ADD CONSTRAINT "GpodderAppPasswords_pkey" PRIMARY KEY (apppasswordid);

--
-- Name: GpodderDeviceSubscriptions GpodderDeviceSubscriptions_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public."GpodderDeviceSubscriptions"
    ADD CONSTRAINT "GpodderDeviceSubscriptions_pkey" PRIMARY KEY (deviceid, podcasturl);

--
-- Name: GpodderDevices GpodderDevices_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public."GpodderDevices"
    ADD CONSTRAINT "GpodderDevices_pkey" PRIMARY KEY (deviceid);

--
-- Name: GpodderDevices GpodderDevices_userid_devicename_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public."GpodderDevices"
    ADD CONSTRAINT "GpodderDevices_userid_devicename_key" UNIQUE (userid, devicename);

--
-- Name: GpodderSessions GpodderSessions_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public."GpodderSessions"
    ADD CONSTRAINT "GpodderSessions_pkey" PRIMARY KEY (sessionid);

--
-- Name: GpodderSessions GpodderSessions_sessiontoken_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public."GpodderSessions"
    ADD CONSTRAINT "GpodderSessions_sessiontoken_key" UNIQUE (sessiontoken);

--
-- Name: GpodderSubscriptionSnapshot GpodderSubscriptionSnapshot_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public."GpodderSubscriptionSnapshot"
    ADD CONSTRAINT "GpodderSubscriptionSnapshot_pkey" PRIMARY KEY (snapshotid);

--
-- Name: GpodderSubscriptionSnapshot GpodderSubscriptionSnapshot_userid_synctarget_feedurl_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public."GpodderSubscriptionSnapshot"
    ADD CONSTRAINT "GpodderSubscriptionSnapshot_userid_synctarget_feedurl_key" UNIQUE (userid, synctarget, feedurl);

--
-- Name: GpodderSyncDevicePairs GpodderSyncDevicePairs_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public."GpodderSyncDevicePairs"
    ADD CONSTRAINT "GpodderSyncDevicePairs_pkey" PRIMARY KEY (pairid);

--
-- Name: GpodderSyncDevicePairs GpodderSyncDevicePairs_userid_deviceid1_deviceid2_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public."GpodderSyncDevicePairs"
    ADD CONSTRAINT "GpodderSyncDevicePairs_userid_deviceid1_deviceid2_key" UNIQUE (userid, deviceid1, deviceid2);

--
-- Name: GpodderSyncDeviceState GpodderSyncDeviceState_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public."GpodderSyncDeviceState"
    ADD CONSTRAINT "GpodderSyncDeviceState_pkey" PRIMARY KEY (devicestateid);

--
-- Name: GpodderSyncDeviceState GpodderSyncDeviceState_userid_deviceid_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public."GpodderSyncDeviceState"
    ADD CONSTRAINT "GpodderSyncDeviceState_userid_deviceid_key" UNIQUE (userid, deviceid);

--
-- Name: GpodderSyncEpisodeActions GpodderSyncEpisodeActions_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public."GpodderSyncEpisodeActions"
    ADD CONSTRAINT "GpodderSyncEpisodeActions_pkey" PRIMARY KEY (actionid);

--
-- Name: GpodderSyncMigrations GpodderSyncMigrations_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public."GpodderSyncMigrations"
    ADD CONSTRAINT "GpodderSyncMigrations_pkey" PRIMARY KEY (version);

--
-- Name: GpodderSyncPodcastListEntries GpodderSyncPodcastListEntries_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public."GpodderSyncPodcastListEntries"
    ADD CONSTRAINT "GpodderSyncPodcastListEntries_pkey" PRIMARY KEY (entryid);

--
-- Name: GpodderSyncPodcastLists GpodderSyncPodcastLists_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public."GpodderSyncPodcastLists"
    ADD CONSTRAINT "GpodderSyncPodcastLists_pkey" PRIMARY KEY (listid);

--
-- Name: GpodderSyncPodcastLists GpodderSyncPodcastLists_userid_name_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public."GpodderSyncPodcastLists"
    ADD CONSTRAINT "GpodderSyncPodcastLists_userid_name_key" UNIQUE (userid, name);

--
-- Name: GpodderSyncSettings GpodderSyncSettings_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public."GpodderSyncSettings"
    ADD CONSTRAINT "GpodderSyncSettings_pkey" PRIMARY KEY (settingid);

--
-- Name: GpodderSyncState GpodderSyncState_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public."GpodderSyncState"
    ADD CONSTRAINT "GpodderSyncState_pkey" PRIMARY KEY (syncstateid);

--
-- Name: GpodderSyncState GpodderSyncState_userid_deviceid_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public."GpodderSyncState"
    ADD CONSTRAINT "GpodderSyncState_userid_deviceid_key" UNIQUE (userid, deviceid);

--
-- Name: GpodderSyncSubscriptions GpodderSyncSubscriptions_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public."GpodderSyncSubscriptions"
    ADD CONSTRAINT "GpodderSyncSubscriptions_pkey" PRIMARY KEY (subscriptionid);

--
-- Name: InAppNotifications InAppNotifications_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public."InAppNotifications"
    ADD CONSTRAINT "InAppNotifications_pkey" PRIMARY KEY (notificationid);

--
-- Name: OIDCProviders OIDCProviders_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public."OIDCProviders"
    ADD CONSTRAINT "OIDCProviders_pkey" PRIMARY KEY (providerid);

--
-- Name: PersonExternalEpisodes PersonExternalEpisodes_personid_episodeurl_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public."PersonExternalEpisodes"
    ADD CONSTRAINT "PersonExternalEpisodes_personid_episodeurl_key" UNIQUE (personid, episodeurl);

--
-- Name: PersonExternalEpisodes PersonExternalEpisodes_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public."PersonExternalEpisodes"
    ADD CONSTRAINT "PersonExternalEpisodes_pkey" PRIMARY KEY (id);

--
-- Name: PersonFollows PersonFollows_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public."PersonFollows"
    ADD CONSTRAINT "PersonFollows_pkey" PRIMARY KEY (userid, personid);

--
-- Name: Persons Persons_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public."Persons"
    ADD CONSTRAINT "Persons_pkey" PRIMARY KEY (personid);

--
-- Name: Persons Persons_podpeopleid_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public."Persons"
    ADD CONSTRAINT "Persons_podpeopleid_key" UNIQUE (podpeopleid);

--
-- Name: PlaylistContents PlaylistContents_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public."PlaylistContents"
    ADD CONSTRAINT "PlaylistContents_pkey" PRIMARY KEY (playlistcontentid);

--
-- Name: Playlists Playlists_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public."Playlists"
    ADD CONSTRAINT "Playlists_pkey" PRIMARY KEY (playlistid);

--
-- Name: Playlists Playlists_userid_name_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public."Playlists"
    ADD CONSTRAINT "Playlists_userid_name_key" UNIQUE (userid, name);

--
-- Name: PodcastFeedAliases PodcastFeedAliases_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public."PodcastFeedAliases"
    ADD CONSTRAINT "PodcastFeedAliases_pkey" PRIMARY KEY (aliasid);

--
-- Name: PodcastPeople PodcastPeople_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public."PodcastPeople"
    ADD CONSTRAINT "PodcastPeople_pkey" PRIMARY KEY (podcastid, personid, role, source);

--
-- Name: Podcasts Podcasts_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public."Podcasts"
    ADD CONSTRAINT "Podcasts_pkey" PRIMARY KEY (podcastid);

--
-- Name: RecommendationCache RecommendationCache_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public."RecommendationCache"
    ADD CONSTRAINT "RecommendationCache_pkey" PRIMARY KEY (userid);

--
-- Name: RssKeys RssKeys_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public."RssKeys"
    ADD CONSTRAINT "RssKeys_pkey" PRIMARY KEY (rsskeyid);

--
-- Name: SavedEpisodes SavedEpisodes_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public."SavedEpisodes"
    ADD CONSTRAINT "SavedEpisodes_pkey" PRIMARY KEY (saveid);

--
-- Name: SavedVideos SavedVideos_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public."SavedVideos"
    ADD CONSTRAINT "SavedVideos_pkey" PRIMARY KEY (saveid);

--
-- Name: ScheduledBackups ScheduledBackups_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public."ScheduledBackups"
    ADD CONSTRAINT "ScheduledBackups_pkey" PRIMARY KEY (id);

--
-- Name: ScheduledBackups ScheduledBackups_userid_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public."ScheduledBackups"
    ADD CONSTRAINT "ScheduledBackups_userid_key" UNIQUE (userid);

--
-- Name: Sessions Sessions_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public."Sessions"
    ADD CONSTRAINT "Sessions_pkey" PRIMARY KEY (sessionid);

--
-- Name: SharedEpisodes SharedEpisodes_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public."SharedEpisodes"
    ADD CONSTRAINT "SharedEpisodes_pkey" PRIMARY KEY (sharedepisodeid);

--
-- Name: SharedEpisodes SharedEpisodes_sharecode_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public."SharedEpisodes"
    ADD CONSTRAINT "SharedEpisodes_sharecode_key" UNIQUE (sharecode);

--
-- Name: SyncImportFailures SyncImportFailures_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public."SyncImportFailures"
    ADD CONSTRAINT "SyncImportFailures_pkey" PRIMARY KEY (failureid);

--
-- Name: SyncTargets SyncTargets_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public."SyncTargets"
    ADD CONSTRAINT "SyncTargets_pkey" PRIMARY KEY (targetid);

--
-- Name: UserEpisodeHistory UserEpisodeHistory_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public."UserEpisodeHistory"
    ADD CONSTRAINT "UserEpisodeHistory_pkey" PRIMARY KEY (userepisodehistoryid);

--
-- Name: UserEpisodeState UserEpisodeState_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public."UserEpisodeState"
    ADD CONSTRAINT "UserEpisodeState_pkey" PRIMARY KEY (userid, episodeid);

--
-- Name: UserNotificationSettings UserNotificationSettings_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public."UserNotificationSettings"
    ADD CONSTRAINT "UserNotificationSettings_pkey" PRIMARY KEY (settingid);

--
-- Name: UserNotificationSettings UserNotificationSettings_userid_platform_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public."UserNotificationSettings"
    ADD CONSTRAINT "UserNotificationSettings_userid_platform_key" UNIQUE (userid, platform);

--
-- Name: UserSettings UserSettings_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public."UserSettings"
    ADD CONSTRAINT "UserSettings_pkey" PRIMARY KEY (usersettingid);

--
-- Name: UserSettings UserSettings_userid_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public."UserSettings"
    ADD CONSTRAINT "UserSettings_userid_key" UNIQUE (userid);

--
-- Name: UserStats UserStats_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public."UserStats"
    ADD CONSTRAINT "UserStats_pkey" PRIMARY KEY (userstatsid);

--
-- Name: UserStats UserStats_userid_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public."UserStats"
    ADD CONSTRAINT "UserStats_userid_key" UNIQUE (userid);

--
-- Name: UserVideoHistory UserVideoHistory_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public."UserVideoHistory"
    ADD CONSTRAINT "UserVideoHistory_pkey" PRIMARY KEY (uservideohistoryid);

--
-- Name: Users Users_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public."Users"
    ADD CONSTRAINT "Users_pkey" PRIMARY KEY (userid);

--
-- Name: Users Users_username_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public."Users"
    ADD CONSTRAINT "Users_username_key" UNIQUE (username);

--
-- Name: YouTubeVideos YouTubeVideos_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public."YouTubeVideos"
    ADD CONSTRAINT "YouTubeVideos_pkey" PRIMARY KEY (videoid);

--
-- Name: Podcasts podcasts_userid_feedurl_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public."Podcasts"
    ADD CONSTRAINT podcasts_userid_feedurl_key UNIQUE (userid, feedurl);

--
-- Name: Feeds uq_feeds_url_credentials; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public."Feeds"
    ADD CONSTRAINT uq_feeds_url_credentials UNIQUE (feedurlhash, credentialkey);

--
-- Name: PodcastFeedAliases uq_podcast_feed_aliases; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public."PodcastFeedAliases"
    ADD CONSTRAINT uq_podcast_feed_aliases UNIQUE (userid, feedurl);

--
-- Name: SyncImportFailures uq_sync_import_failures; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public."SyncImportFailures"
    ADD CONSTRAINT uq_sync_import_failures UNIQUE (userid, feedurl);

--
-- Name: SyncTargets uq_sync_targets_user; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public."SyncTargets"
    ADD CONSTRAINT uq_sync_targets_user UNIQUE (userid);

--
-- Name: UserEpisodeHistory user_episode_unique; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public."UserEpisodeHistory"
    ADD CONSTRAINT user_episode_unique UNIQUE (userid, episodeid);

--
-- Name: UserVideoHistory user_video_unique; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public."UserVideoHistory"
    ADD CONSTRAINT user_video_unique UNIQUE (userid, videoid);

--
-- Name: idx_ad_skip_review_segmentid; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_ad_skip_review_segmentid ON public."EpisodeAdSkipReview" USING btree (segmentid);

--
-- Name: idx_ad_skip_review_userid; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_ad_skip_review_userid ON public."EpisodeAdSkipReview" USING btree (userid);

--
-- Name: idx_collection_episodes_collectionid; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_collection_episodes_collectionid ON public."CollectionEpisodes" USING btree (collectionid);

--
-- Name: idx_collection_episodes_episodeid; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_collection_episodes_episodeid ON public."CollectionEpisodes" USING btree (episodeid);

--
-- Name: idx_collection_episodes_videoid; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_collection_episodes_videoid ON public."CollectionEpisodes" USING btree (videoid);

--
-- Name: idx_collections_one_default_per_user; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX idx_collections_one_default_per_user ON public."Collections" USING btree (userid) WHERE (isdefault = true);

--
-- Name: idx_collections_userid; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_collections_userid ON public."Collections" USING btree (userid);

--
-- Name: idx_downloadedepisodes_episodeid; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_downloadedepisodes_episodeid ON public."DownloadedEpisodes" USING btree (episodeid);

--
-- Name: idx_downloadedepisodes_userid; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_downloadedepisodes_userid ON public."DownloadedEpisodes" USING btree (userid);

--
-- Name: idx_downloadedepisodes_userid_episodeid; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_downloadedepisodes_userid_episodeid ON public."DownloadedEpisodes" USING btree (userid, episodeid);

--
-- Name: idx_downloadedvideos_userid; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_downloadedvideos_userid ON public."DownloadedVideos" USING btree (userid);

--
-- Name: idx_downloadedvideos_userid_videoid; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_downloadedvideos_userid_videoid ON public."DownloadedVideos" USING btree (userid, videoid);

--
-- Name: idx_downloadedvideos_videoid; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_downloadedvideos_videoid ON public."DownloadedVideos" USING btree (videoid);

--
-- Name: idx_episode_actions_device_timestamp; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_episode_actions_device_timestamp ON public."GpodderSyncEpisodeActions" USING btree (deviceid, "timestamp" DESC) WHERE (deviceid IS NOT NULL);

--
-- Name: idx_episode_actions_podcast_episode; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_episode_actions_podcast_episode ON public."GpodderSyncEpisodeActions" USING btree (userid, podcasturl, episodeurl, "timestamp" DESC);

--
-- Name: idx_episode_actions_since_filter; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_episode_actions_since_filter ON public."GpodderSyncEpisodeActions" USING btree (userid, "timestamp" DESC, deviceid) WHERE ("timestamp" > 0);

--
-- Name: idx_episode_actions_user_timestamp; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_episode_actions_user_timestamp ON public."GpodderSyncEpisodeActions" USING btree (userid, "timestamp" DESC);

--
-- Name: idx_episode_transcripts_episodeid; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_episode_transcripts_episodeid ON public."EpisodeTranscripts" USING btree (episodeid);

--
-- Name: idx_episode_transcripts_fts; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_episode_transcripts_fts ON public."EpisodeTranscripts" USING gin (to_tsvector('simple'::regconfig, COALESCE(transcripttext, ''::text)));

--
-- Name: idx_episode_transcripts_videoid; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_episode_transcripts_videoid ON public."EpisodeTranscripts" USING btree (videoid);

--
-- Name: idx_episodeidaliases_episode; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_episodeidaliases_episode ON public."EpisodeIDAliases" USING btree (episodeid);

--
-- Name: idx_episodepeople_person; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_episodepeople_person ON public."EpisodePeople" USING btree (personid);

--
-- Name: idx_episodequeue_episodeid; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_episodequeue_episodeid ON public."EpisodeQueue" USING btree (episodeid);

--
-- Name: idx_episodequeue_queueposition; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_episodequeue_queueposition ON public."EpisodeQueue" USING btree (queueposition);

--
-- Name: idx_episodequeue_userid; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_episodequeue_userid ON public."EpisodeQueue" USING btree (userid);

--
-- Name: idx_episodequeue_userid_queueposition; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_episodequeue_userid_queueposition ON public."EpisodeQueue" USING btree (userid, queueposition);

--
-- Name: idx_episodes_completed; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_episodes_completed ON public."Episodes" USING btree (completed);

--
-- Name: idx_episodes_episodepubdate; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_episodes_episodepubdate ON public."Episodes" USING btree (episodepubdate);

--
-- Name: idx_episodes_episodeurl_hash; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_episodes_episodeurl_hash ON public."Episodes" USING hash (episodeurl);

--
-- Name: idx_episodes_feedid_guid_unique; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX idx_episodes_feedid_guid_unique ON public."Episodes" USING btree (feedid, episodeguid) WHERE (episodeguid IS NOT NULL);

--
-- Name: idx_episodes_feedid_pubdate; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_episodes_feedid_pubdate ON public."Episodes" USING btree (feedid, episodepubdate);

--
-- Name: idx_episodes_podcastid; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_episodes_podcastid ON public."Episodes" USING btree (podcastid);

--
-- Name: idx_episodes_podcastid_pubdate; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_episodes_podcastid_pubdate ON public."Episodes" USING btree (podcastid, episodepubdate DESC);

--
-- Name: idx_episodes_podcastid_title; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_episodes_podcastid_title ON public."Episodes" USING btree (podcastid, episodetitle);

--
-- Name: idx_feeds_nextrefreshat; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_feeds_nextrefreshat ON public."Feeds" USING btree (nextrefreshat);

--
-- Name: idx_gpodder_app_passwords_user; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_gpodder_app_passwords_user ON public."GpodderAppPasswords" USING btree (userid);

--
-- Name: idx_gpodder_devices_user_name; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_gpodder_devices_user_name ON public."GpodderDevices" USING btree (userid, devicename) WHERE (isactive = true);

--
-- Name: idx_gpodder_devices_user_systemrole; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX idx_gpodder_devices_user_systemrole ON public."GpodderDevices" USING btree (userid, systemrole);

--
-- Name: idx_gpodder_devices_userid; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_gpodder_devices_userid ON public."GpodderDevices" USING btree (userid);

--
-- Name: idx_gpodder_episode_actions_episodeid; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_gpodder_episode_actions_episodeid ON public."GpodderSyncEpisodeActions" USING btree (episodeid, userid);

--
-- Name: idx_gpodder_episode_actions_unmatched; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_gpodder_episode_actions_unmatched ON public."GpodderSyncEpisodeActions" USING btree (userid) WHERE (episodeid IS NULL);

--
-- Name: idx_gpodder_episode_actions_user_actionid; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_gpodder_episode_actions_user_actionid ON public."GpodderSyncEpisodeActions" USING btree (userid, actionid);

--
-- Name: idx_gpodder_episode_actions_user_serverts; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_gpodder_episode_actions_user_serverts ON public."GpodderSyncEpisodeActions" USING btree (userid, serverts);

--
-- Name: idx_gpodder_sessions_expires; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_gpodder_sessions_expires ON public."GpodderSessions" USING btree (expiresat);

--
-- Name: idx_gpodder_sessions_token; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_gpodder_sessions_token ON public."GpodderSessions" USING btree (sessiontoken);

--
-- Name: idx_gpodder_sessions_userid; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_gpodder_sessions_userid ON public."GpodderSessions" USING btree (userid);

--
-- Name: idx_gpodder_subscriptions_user_serverts; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_gpodder_subscriptions_user_serverts ON public."GpodderSyncSubscriptions" USING btree (userid, serverts);

--
-- Name: idx_gpodder_subscriptions_user_subid; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_gpodder_subscriptions_user_subid ON public."GpodderSyncSubscriptions" USING btree (userid, subscriptionid);

--
-- Name: idx_gpodder_subsnapshot_user_target; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_gpodder_subsnapshot_user_target ON public."GpodderSubscriptionSnapshot" USING btree (userid, synctarget);

--
-- Name: idx_gpodder_sync_episode_actions_userid; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_gpodder_sync_episode_actions_userid ON public."GpodderSyncEpisodeActions" USING btree (userid);

--
-- Name: idx_gpodder_sync_podcast_lists_userid; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_gpodder_sync_podcast_lists_userid ON public."GpodderSyncPodcastLists" USING btree (userid);

--
-- Name: idx_gpodder_sync_subs_complex_query; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_gpodder_sync_subs_complex_query ON public."GpodderSyncSubscriptions" USING btree (userid, deviceid, action, "timestamp" DESC, podcasturl);

--
-- Name: idx_gpodder_sync_subs_podcast_url_user; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_gpodder_sync_subs_podcast_url_user ON public."GpodderSyncSubscriptions" USING btree (userid, podcasturl, "timestamp" DESC);

--
-- Name: idx_gpodder_sync_subs_user_action_timestamp; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_gpodder_sync_subs_user_action_timestamp ON public."GpodderSyncSubscriptions" USING btree (userid, action, "timestamp" DESC);

--
-- Name: idx_gpodder_sync_subs_user_device_timestamp; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_gpodder_sync_subs_user_device_timestamp ON public."GpodderSyncSubscriptions" USING btree (userid, deviceid, "timestamp" DESC);

--
-- Name: idx_gpodder_sync_subscriptions_deviceid; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_gpodder_sync_subscriptions_deviceid ON public."GpodderSyncSubscriptions" USING btree (deviceid);

--
-- Name: idx_gpodder_sync_subscriptions_userid; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_gpodder_sync_subscriptions_userid ON public."GpodderSyncSubscriptions" USING btree (userid);

--
-- Name: idx_gpodder_syncstate_userid_deviceid; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_gpodder_syncstate_userid_deviceid ON public."GpodderSyncState" USING btree (userid, deviceid);

--
-- Name: idx_inappnotifications_user; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_inappnotifications_user ON public."InAppNotifications" USING btree (userid, expiresat);

--
-- Name: idx_personexternal_date; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_personexternal_date ON public."PersonExternalEpisodes" USING btree (personid, episodepubdate DESC);

--
-- Name: idx_personfollows_person; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_personfollows_person ON public."PersonFollows" USING btree (personid);

--
-- Name: idx_persons_name_normalized; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_persons_name_normalized ON public."Persons" USING btree (namenormalized);

--
-- Name: idx_playlist_contents_episodeid; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_playlist_contents_episodeid ON public."PlaylistContents" USING btree (episodeid);

--
-- Name: idx_playlist_contents_playlistid; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_playlist_contents_playlistid ON public."PlaylistContents" USING btree (playlistid);

--
-- Name: idx_playlist_contents_videoid; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_playlist_contents_videoid ON public."PlaylistContents" USING btree (videoid);

--
-- Name: idx_playlists_userid; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_playlists_userid ON public."Playlists" USING btree (userid);

--
-- Name: idx_podcast_feed_aliases_podcast; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_podcast_feed_aliases_podcast ON public."PodcastFeedAliases" USING btree (podcastid);

--
-- Name: idx_podcastpeople_person; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_podcastpeople_person ON public."PodcastPeople" USING btree (personid);

--
-- Name: idx_podcasts_displaypodcast; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_podcasts_displaypodcast ON public."Podcasts" USING btree (displaypodcast);

--
-- Name: idx_podcasts_feedid; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_podcasts_feedid ON public."Podcasts" USING btree (feedid);

--
-- Name: idx_podcasts_feedurl; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_podcasts_feedurl ON public."Podcasts" USING hash (feedurl);

--
-- Name: idx_podcasts_nextrefreshat; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_podcasts_nextrefreshat ON public."Podcasts" USING btree (nextrefreshat);

--
-- Name: idx_podcasts_userid; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_podcasts_userid ON public."Podcasts" USING btree (userid);

--
-- Name: idx_savedepisodes_episodeid; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_savedepisodes_episodeid ON public."SavedEpisodes" USING btree (episodeid);

--
-- Name: idx_savedepisodes_userid; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_savedepisodes_userid ON public."SavedEpisodes" USING btree (userid);

--
-- Name: idx_savedepisodes_userid_episodeid; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_savedepisodes_userid_episodeid ON public."SavedEpisodes" USING btree (userid, episodeid);

--
-- Name: idx_savedvideos_userid; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_savedvideos_userid ON public."SavedVideos" USING btree (userid);

--
-- Name: idx_savedvideos_userid_videoid; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_savedvideos_userid_videoid ON public."SavedVideos" USING btree (userid, videoid);

--
-- Name: idx_savedvideos_videoid; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_savedvideos_videoid ON public."SavedVideos" USING btree (videoid);

--
-- Name: idx_scheduled_backups_enabled; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_scheduled_backups_enabled ON public."ScheduledBackups" USING btree (enabled);

--
-- Name: idx_skip_segments_episodeid; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_skip_segments_episodeid ON public."EpisodeSkipSegments" USING btree (episodeid);

--
-- Name: idx_skip_segments_videoid; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_skip_segments_videoid ON public."EpisodeSkipSegments" USING btree (videoid);

--
-- Name: idx_sync_import_failures_next; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_sync_import_failures_next ON public."SyncImportFailures" USING btree (nextattemptat);

--
-- Name: idx_userepisodehistory_episodeid; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_userepisodehistory_episodeid ON public."UserEpisodeHistory" USING btree (episodeid);

--
-- Name: idx_userepisodehistory_userid; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_userepisodehistory_userid ON public."UserEpisodeHistory" USING btree (userid);

--
-- Name: idx_userepisodehistory_userid_episodeid; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_userepisodehistory_userid_episodeid ON public."UserEpisodeHistory" USING btree (userid, episodeid);

--
-- Name: idx_userepisodehistory_userid_listendate; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_userepisodehistory_userid_listendate ON public."UserEpisodeHistory" USING btree (userid, listendate DESC);

--
-- Name: idx_userepisodestate_episode; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_userepisodestate_episode ON public."UserEpisodeState" USING btree (episodeid);

--
-- Name: idx_uservideohistory_userid; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_uservideohistory_userid ON public."UserVideoHistory" USING btree (userid);

--
-- Name: idx_uservideohistory_userid_videoid; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_uservideohistory_userid_videoid ON public."UserVideoHistory" USING btree (userid, videoid);

--
-- Name: idx_uservideohistory_videoid; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_uservideohistory_videoid ON public."UserVideoHistory" USING btree (videoid);

--
-- Name: idx_youtubevideos_completed; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_youtubevideos_completed ON public."YouTubeVideos" USING btree (completed);

--
-- Name: idx_youtubevideos_podcastid; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_youtubevideos_podcastid ON public."YouTubeVideos" USING btree (podcastid);

--
-- Name: idx_youtubevideos_podcastid_publishedat; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_youtubevideos_podcastid_publishedat ON public."YouTubeVideos" USING btree (podcastid, publishedat DESC);

--
-- Name: idx_youtubevideos_publishedat; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_youtubevideos_publishedat ON public."YouTubeVideos" USING btree (publishedat);

--
-- Name: APIKeys APIKeys_userid_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public."APIKeys"
    ADD CONSTRAINT "APIKeys_userid_fkey" FOREIGN KEY (userid) REFERENCES public."Users"(userid) ON DELETE CASCADE;

--
-- Name: CollectionEpisodes CollectionEpisodes_collectionid_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public."CollectionEpisodes"
    ADD CONSTRAINT "CollectionEpisodes_collectionid_fkey" FOREIGN KEY (collectionid) REFERENCES public."Collections"(collectionid) ON DELETE CASCADE;

--
-- Name: CollectionEpisodes CollectionEpisodes_episodeid_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public."CollectionEpisodes"
    ADD CONSTRAINT "CollectionEpisodes_episodeid_fkey" FOREIGN KEY (episodeid) REFERENCES public."Episodes"(episodeid) ON DELETE CASCADE;

--
-- Name: CollectionEpisodes CollectionEpisodes_videoid_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public."CollectionEpisodes"
    ADD CONSTRAINT "CollectionEpisodes_videoid_fkey" FOREIGN KEY (videoid) REFERENCES public."YouTubeVideos"(videoid) ON DELETE CASCADE;

--
-- Name: Collections Collections_userid_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public."Collections"
    ADD CONSTRAINT "Collections_userid_fkey" FOREIGN KEY (userid) REFERENCES public."Users"(userid) ON DELETE CASCADE;

--
-- Name: CustomThemes CustomThemes_userid_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public."CustomThemes"
    ADD CONSTRAINT "CustomThemes_userid_fkey" FOREIGN KEY (userid) REFERENCES public."Users"(userid) ON DELETE CASCADE;

--
-- Name: DownloadedEpisodes DownloadedEpisodes_episodeid_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public."DownloadedEpisodes"
    ADD CONSTRAINT "DownloadedEpisodes_episodeid_fkey" FOREIGN KEY (episodeid) REFERENCES public."Episodes"(episodeid);

--
-- Name: DownloadedEpisodes DownloadedEpisodes_userid_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public."DownloadedEpisodes"
    ADD CONSTRAINT "DownloadedEpisodes_userid_fkey" FOREIGN KEY (userid) REFERENCES public."Users"(userid);

--
-- Name: DownloadedVideos DownloadedVideos_userid_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public."DownloadedVideos"
    ADD CONSTRAINT "DownloadedVideos_userid_fkey" FOREIGN KEY (userid) REFERENCES public."Users"(userid);

--
-- Name: DownloadedVideos DownloadedVideos_videoid_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public."DownloadedVideos"
    ADD CONSTRAINT "DownloadedVideos_videoid_fkey" FOREIGN KEY (videoid) REFERENCES public."YouTubeVideos"(videoid);

--
-- Name: EpisodeAdSkipReview EpisodeAdSkipReview_segmentid_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public."EpisodeAdSkipReview"
    ADD CONSTRAINT "EpisodeAdSkipReview_segmentid_fkey" FOREIGN KEY (segmentid) REFERENCES public."EpisodeSkipSegments"(segmentid) ON DELETE CASCADE;

--
-- Name: EpisodeAdSkipReview EpisodeAdSkipReview_userid_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public."EpisodeAdSkipReview"
    ADD CONSTRAINT "EpisodeAdSkipReview_userid_fkey" FOREIGN KEY (userid) REFERENCES public."Users"(userid) ON DELETE CASCADE;

--
-- Name: EpisodeIDAliases EpisodeIDAliases_episodeid_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public."EpisodeIDAliases"
    ADD CONSTRAINT "EpisodeIDAliases_episodeid_fkey" FOREIGN KEY (episodeid) REFERENCES public."Episodes"(episodeid) ON DELETE CASCADE;

--
-- Name: EpisodePeople EpisodePeople_episodeid_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public."EpisodePeople"
    ADD CONSTRAINT "EpisodePeople_episodeid_fkey" FOREIGN KEY (episodeid) REFERENCES public."Episodes"(episodeid) ON DELETE CASCADE;

--
-- Name: EpisodePeople EpisodePeople_personid_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public."EpisodePeople"
    ADD CONSTRAINT "EpisodePeople_personid_fkey" FOREIGN KEY (personid) REFERENCES public."Persons"(personid) ON DELETE CASCADE;

--
-- Name: EpisodeQueue EpisodeQueue_userid_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public."EpisodeQueue"
    ADD CONSTRAINT "EpisodeQueue_userid_fkey" FOREIGN KEY (userid) REFERENCES public."Users"(userid);

--
-- Name: EpisodeSkipSegments EpisodeSkipSegments_episodeid_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public."EpisodeSkipSegments"
    ADD CONSTRAINT "EpisodeSkipSegments_episodeid_fkey" FOREIGN KEY (episodeid) REFERENCES public."Episodes"(episodeid) ON DELETE CASCADE;

--
-- Name: EpisodeSkipSegments EpisodeSkipSegments_videoid_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public."EpisodeSkipSegments"
    ADD CONSTRAINT "EpisodeSkipSegments_videoid_fkey" FOREIGN KEY (videoid) REFERENCES public."YouTubeVideos"(videoid) ON DELETE CASCADE;

--
-- Name: EpisodeTranscripts EpisodeTranscripts_episodeid_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public."EpisodeTranscripts"
    ADD CONSTRAINT "EpisodeTranscripts_episodeid_fkey" FOREIGN KEY (episodeid) REFERENCES public."Episodes"(episodeid) ON DELETE CASCADE;

--
-- Name: EpisodeTranscripts EpisodeTranscripts_videoid_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public."EpisodeTranscripts"
    ADD CONSTRAINT "EpisodeTranscripts_videoid_fkey" FOREIGN KEY (videoid) REFERENCES public."YouTubeVideos"(videoid) ON DELETE CASCADE;

--
-- Name: GpodderAppPasswords GpodderAppPasswords_userid_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public."GpodderAppPasswords"
    ADD CONSTRAINT "GpodderAppPasswords_userid_fkey" FOREIGN KEY (userid) REFERENCES public."Users"(userid) ON DELETE CASCADE;

--
-- Name: GpodderDeviceSubscriptions GpodderDeviceSubscriptions_deviceid_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public."GpodderDeviceSubscriptions"
    ADD CONSTRAINT "GpodderDeviceSubscriptions_deviceid_fkey" FOREIGN KEY (deviceid) REFERENCES public."GpodderDevices"(deviceid) ON DELETE CASCADE;

--
-- Name: GpodderDevices GpodderDevices_userid_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public."GpodderDevices"
    ADD CONSTRAINT "GpodderDevices_userid_fkey" FOREIGN KEY (userid) REFERENCES public."Users"(userid) ON DELETE CASCADE;

--
-- Name: GpodderSessions GpodderSessions_userid_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public."GpodderSessions"
    ADD CONSTRAINT "GpodderSessions_userid_fkey" FOREIGN KEY (userid) REFERENCES public."Users"(userid) ON DELETE CASCADE;

--
-- Name: GpodderSubscriptionSnapshot GpodderSubscriptionSnapshot_userid_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public."GpodderSubscriptionSnapshot"
    ADD CONSTRAINT "GpodderSubscriptionSnapshot_userid_fkey" FOREIGN KEY (userid) REFERENCES public."Users"(userid) ON DELETE CASCADE;

--
-- Name: GpodderSyncDevicePairs GpodderSyncDevicePairs_deviceid1_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public."GpodderSyncDevicePairs"
    ADD CONSTRAINT "GpodderSyncDevicePairs_deviceid1_fkey" FOREIGN KEY (deviceid1) REFERENCES public."GpodderDevices"(deviceid) ON DELETE CASCADE;

--
-- Name: GpodderSyncDevicePairs GpodderSyncDevicePairs_deviceid2_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public."GpodderSyncDevicePairs"
    ADD CONSTRAINT "GpodderSyncDevicePairs_deviceid2_fkey" FOREIGN KEY (deviceid2) REFERENCES public."GpodderDevices"(deviceid) ON DELETE CASCADE;

--
-- Name: GpodderSyncDevicePairs GpodderSyncDevicePairs_userid_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public."GpodderSyncDevicePairs"
    ADD CONSTRAINT "GpodderSyncDevicePairs_userid_fkey" FOREIGN KEY (userid) REFERENCES public."Users"(userid) ON DELETE CASCADE;

--
-- Name: GpodderSyncDeviceState GpodderSyncDeviceState_deviceid_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public."GpodderSyncDeviceState"
    ADD CONSTRAINT "GpodderSyncDeviceState_deviceid_fkey" FOREIGN KEY (deviceid) REFERENCES public."GpodderDevices"(deviceid) ON DELETE CASCADE;

--
-- Name: GpodderSyncDeviceState GpodderSyncDeviceState_userid_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public."GpodderSyncDeviceState"
    ADD CONSTRAINT "GpodderSyncDeviceState_userid_fkey" FOREIGN KEY (userid) REFERENCES public."Users"(userid) ON DELETE CASCADE;

--
-- Name: GpodderSyncEpisodeActions GpodderSyncEpisodeActions_userid_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public."GpodderSyncEpisodeActions"
    ADD CONSTRAINT "GpodderSyncEpisodeActions_userid_fkey" FOREIGN KEY (userid) REFERENCES public."Users"(userid) ON DELETE CASCADE;

--
-- Name: GpodderSyncPodcastListEntries GpodderSyncPodcastListEntries_listid_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public."GpodderSyncPodcastListEntries"
    ADD CONSTRAINT "GpodderSyncPodcastListEntries_listid_fkey" FOREIGN KEY (listid) REFERENCES public."GpodderSyncPodcastLists"(listid) ON DELETE CASCADE;

--
-- Name: GpodderSyncPodcastLists GpodderSyncPodcastLists_userid_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public."GpodderSyncPodcastLists"
    ADD CONSTRAINT "GpodderSyncPodcastLists_userid_fkey" FOREIGN KEY (userid) REFERENCES public."Users"(userid) ON DELETE CASCADE;

--
-- Name: GpodderSyncSettings GpodderSyncSettings_deviceid_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public."GpodderSyncSettings"
    ADD CONSTRAINT "GpodderSyncSettings_deviceid_fkey" FOREIGN KEY (deviceid) REFERENCES public."GpodderDevices"(deviceid) ON DELETE CASCADE;

--
-- Name: GpodderSyncSettings GpodderSyncSettings_userid_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public."GpodderSyncSettings"
    ADD CONSTRAINT "GpodderSyncSettings_userid_fkey" FOREIGN KEY (userid) REFERENCES public."Users"(userid) ON DELETE CASCADE;

--
-- Name: GpodderSyncState GpodderSyncState_deviceid_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public."GpodderSyncState"
    ADD CONSTRAINT "GpodderSyncState_deviceid_fkey" FOREIGN KEY (deviceid) REFERENCES public."GpodderDevices"(deviceid) ON DELETE CASCADE;

--
-- Name: GpodderSyncState GpodderSyncState_userid_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public."GpodderSyncState"
    ADD CONSTRAINT "GpodderSyncState_userid_fkey" FOREIGN KEY (userid) REFERENCES public."Users"(userid) ON DELETE CASCADE;

--
-- Name: GpodderSyncSubscriptions GpodderSyncSubscriptions_userid_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public."GpodderSyncSubscriptions"
    ADD CONSTRAINT "GpodderSyncSubscriptions_userid_fkey" FOREIGN KEY (userid) REFERENCES public."Users"(userid) ON DELETE CASCADE;

--
-- Name: InAppNotifications InAppNotifications_userid_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public."InAppNotifications"
    ADD CONSTRAINT "InAppNotifications_userid_fkey" FOREIGN KEY (userid) REFERENCES public."Users"(userid) ON DELETE CASCADE;

--
-- Name: PersonExternalEpisodes PersonExternalEpisodes_personid_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public."PersonExternalEpisodes"
    ADD CONSTRAINT "PersonExternalEpisodes_personid_fkey" FOREIGN KEY (personid) REFERENCES public."Persons"(personid) ON DELETE CASCADE;

--
-- Name: PersonFollows PersonFollows_personid_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public."PersonFollows"
    ADD CONSTRAINT "PersonFollows_personid_fkey" FOREIGN KEY (personid) REFERENCES public."Persons"(personid) ON DELETE CASCADE;

--
-- Name: PersonFollows PersonFollows_userid_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public."PersonFollows"
    ADD CONSTRAINT "PersonFollows_userid_fkey" FOREIGN KEY (userid) REFERENCES public."Users"(userid) ON DELETE CASCADE;

--
-- Name: PlaylistContents PlaylistContents_episodeid_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public."PlaylistContents"
    ADD CONSTRAINT "PlaylistContents_episodeid_fkey" FOREIGN KEY (episodeid) REFERENCES public."Episodes"(episodeid) ON DELETE CASCADE;

--
-- Name: PlaylistContents PlaylistContents_playlistid_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public."PlaylistContents"
    ADD CONSTRAINT "PlaylistContents_playlistid_fkey" FOREIGN KEY (playlistid) REFERENCES public."Playlists"(playlistid) ON DELETE CASCADE;

--
-- Name: PlaylistContents PlaylistContents_videoid_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public."PlaylistContents"
    ADD CONSTRAINT "PlaylistContents_videoid_fkey" FOREIGN KEY (videoid) REFERENCES public."YouTubeVideos"(videoid) ON DELETE CASCADE;

--
-- Name: Playlists Playlists_userid_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public."Playlists"
    ADD CONSTRAINT "Playlists_userid_fkey" FOREIGN KEY (userid) REFERENCES public."Users"(userid) ON DELETE CASCADE;

--
-- Name: PodcastFeedAliases PodcastFeedAliases_podcastid_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public."PodcastFeedAliases"
    ADD CONSTRAINT "PodcastFeedAliases_podcastid_fkey" FOREIGN KEY (podcastid) REFERENCES public."Podcasts"(podcastid) ON DELETE CASCADE;

--
-- Name: PodcastFeedAliases PodcastFeedAliases_userid_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public."PodcastFeedAliases"
    ADD CONSTRAINT "PodcastFeedAliases_userid_fkey" FOREIGN KEY (userid) REFERENCES public."Users"(userid) ON DELETE CASCADE;

--
-- Name: PodcastPeople PodcastPeople_personid_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public."PodcastPeople"
    ADD CONSTRAINT "PodcastPeople_personid_fkey" FOREIGN KEY (personid) REFERENCES public."Persons"(personid) ON DELETE CASCADE;

--
-- Name: PodcastPeople PodcastPeople_podcastid_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public."PodcastPeople"
    ADD CONSTRAINT "PodcastPeople_podcastid_fkey" FOREIGN KEY (podcastid) REFERENCES public."Podcasts"(podcastid) ON DELETE CASCADE;

--
-- Name: Podcasts Podcasts_userid_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public."Podcasts"
    ADD CONSTRAINT "Podcasts_userid_fkey" FOREIGN KEY (userid) REFERENCES public."Users"(userid);

--
-- Name: RecommendationCache RecommendationCache_userid_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public."RecommendationCache"
    ADD CONSTRAINT "RecommendationCache_userid_fkey" FOREIGN KEY (userid) REFERENCES public."Users"(userid) ON DELETE CASCADE;

--
-- Name: RssKeyMap RssKeyMap_rsskeyid_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public."RssKeyMap"
    ADD CONSTRAINT "RssKeyMap_rsskeyid_fkey" FOREIGN KEY (rsskeyid) REFERENCES public."RssKeys"(rsskeyid) ON DELETE CASCADE;

--
-- Name: RssKeys RssKeys_userid_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public."RssKeys"
    ADD CONSTRAINT "RssKeys_userid_fkey" FOREIGN KEY (userid) REFERENCES public."Users"(userid) ON DELETE CASCADE;

--
-- Name: SavedEpisodes SavedEpisodes_episodeid_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public."SavedEpisodes"
    ADD CONSTRAINT "SavedEpisodes_episodeid_fkey" FOREIGN KEY (episodeid) REFERENCES public."Episodes"(episodeid);

--
-- Name: SavedEpisodes SavedEpisodes_userid_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public."SavedEpisodes"
    ADD CONSTRAINT "SavedEpisodes_userid_fkey" FOREIGN KEY (userid) REFERENCES public."Users"(userid);

--
-- Name: SavedVideos SavedVideos_userid_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public."SavedVideos"
    ADD CONSTRAINT "SavedVideos_userid_fkey" FOREIGN KEY (userid) REFERENCES public."Users"(userid);

--
-- Name: SavedVideos SavedVideos_videoid_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public."SavedVideos"
    ADD CONSTRAINT "SavedVideos_videoid_fkey" FOREIGN KEY (videoid) REFERENCES public."YouTubeVideos"(videoid);

--
-- Name: ScheduledBackups ScheduledBackups_userid_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public."ScheduledBackups"
    ADD CONSTRAINT "ScheduledBackups_userid_fkey" FOREIGN KEY (userid) REFERENCES public."Users"(userid) ON DELETE CASCADE;

--
-- Name: Sessions Sessions_userid_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public."Sessions"
    ADD CONSTRAINT "Sessions_userid_fkey" FOREIGN KEY (userid) REFERENCES public."Users"(userid) ON DELETE CASCADE;

--
-- Name: SharedEpisodes SharedEpisodes_episodeid_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public."SharedEpisodes"
    ADD CONSTRAINT "SharedEpisodes_episodeid_fkey" FOREIGN KEY (episodeid) REFERENCES public."Episodes"(episodeid) ON DELETE CASCADE;

--
-- Name: SharedEpisodes SharedEpisodes_sharedby_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public."SharedEpisodes"
    ADD CONSTRAINT "SharedEpisodes_sharedby_fkey" FOREIGN KEY (sharedby) REFERENCES public."Users"(userid) ON DELETE CASCADE;

--
-- Name: SharedEpisodes SharedEpisodes_sharedwith_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public."SharedEpisodes"
    ADD CONSTRAINT "SharedEpisodes_sharedwith_fkey" FOREIGN KEY (sharedwith) REFERENCES public."Users"(userid) ON DELETE CASCADE;

--
-- Name: SyncImportFailures SyncImportFailures_userid_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public."SyncImportFailures"
    ADD CONSTRAINT "SyncImportFailures_userid_fkey" FOREIGN KEY (userid) REFERENCES public."Users"(userid) ON DELETE CASCADE;

--
-- Name: SyncTargets SyncTargets_userid_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public."SyncTargets"
    ADD CONSTRAINT "SyncTargets_userid_fkey" FOREIGN KEY (userid) REFERENCES public."Users"(userid) ON DELETE CASCADE;

--
-- Name: UserEpisodeHistory UserEpisodeHistory_episodeid_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public."UserEpisodeHistory"
    ADD CONSTRAINT "UserEpisodeHistory_episodeid_fkey" FOREIGN KEY (episodeid) REFERENCES public."Episodes"(episodeid);

--
-- Name: UserEpisodeHistory UserEpisodeHistory_userid_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public."UserEpisodeHistory"
    ADD CONSTRAINT "UserEpisodeHistory_userid_fkey" FOREIGN KEY (userid) REFERENCES public."Users"(userid);

--
-- Name: UserEpisodeState UserEpisodeState_episodeid_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public."UserEpisodeState"
    ADD CONSTRAINT "UserEpisodeState_episodeid_fkey" FOREIGN KEY (episodeid) REFERENCES public."Episodes"(episodeid) ON DELETE CASCADE;

--
-- Name: UserEpisodeState UserEpisodeState_userid_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public."UserEpisodeState"
    ADD CONSTRAINT "UserEpisodeState_userid_fkey" FOREIGN KEY (userid) REFERENCES public."Users"(userid) ON DELETE CASCADE;

--
-- Name: UserNotificationSettings UserNotificationSettings_userid_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public."UserNotificationSettings"
    ADD CONSTRAINT "UserNotificationSettings_userid_fkey" FOREIGN KEY (userid) REFERENCES public."Users"(userid) ON DELETE CASCADE;

--
-- Name: UserSettings UserSettings_userid_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public."UserSettings"
    ADD CONSTRAINT "UserSettings_userid_fkey" FOREIGN KEY (userid) REFERENCES public."Users"(userid);

--
-- Name: UserStats UserStats_userid_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public."UserStats"
    ADD CONSTRAINT "UserStats_userid_fkey" FOREIGN KEY (userid) REFERENCES public."Users"(userid);

--
-- Name: UserVideoHistory UserVideoHistory_userid_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public."UserVideoHistory"
    ADD CONSTRAINT "UserVideoHistory_userid_fkey" FOREIGN KEY (userid) REFERENCES public."Users"(userid);

--
-- Name: UserVideoHistory UserVideoHistory_videoid_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public."UserVideoHistory"
    ADD CONSTRAINT "UserVideoHistory_videoid_fkey" FOREIGN KEY (videoid) REFERENCES public."YouTubeVideos"(videoid);

--
-- Name: YouTubeVideos YouTubeVideos_podcastid_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public."YouTubeVideos"
    ADD CONSTRAINT "YouTubeVideos_podcastid_fkey" FOREIGN KEY (podcastid) REFERENCES public."Podcasts"(podcastid);

--
-- Name: GpodderSyncEpisodeActions fk_gpodder_episode_actions_device; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public."GpodderSyncEpisodeActions"
    ADD CONSTRAINT fk_gpodder_episode_actions_device FOREIGN KEY (deviceid) REFERENCES public."GpodderDevices"(deviceid) ON DELETE SET NULL;

--
-- Name: GpodderSyncEpisodeActions fk_gpodder_episode_actions_episode; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public."GpodderSyncEpisodeActions"
    ADD CONSTRAINT fk_gpodder_episode_actions_episode FOREIGN KEY (episodeid) REFERENCES public."Episodes"(episodeid) ON DELETE SET NULL;

--
-- Name: GpodderSessions fk_gpodder_sessions_app_password; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public."GpodderSessions"
    ADD CONSTRAINT fk_gpodder_sessions_app_password FOREIGN KEY (apppasswordid) REFERENCES public."GpodderAppPasswords"(apppasswordid) ON DELETE CASCADE;

--
-- Name: GpodderSyncSubscriptions fk_gpodder_subscriptions_device; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public."GpodderSyncSubscriptions"
    ADD CONSTRAINT fk_gpodder_subscriptions_device FOREIGN KEY (deviceid) REFERENCES public."GpodderDevices"(deviceid) ON DELETE SET NULL;

--
-- Name: Users fk_oidc_provider; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public."Users"
    ADD CONSTRAINT fk_oidc_provider FOREIGN KEY (oidc_provider_id) REFERENCES public."OIDCProviders"(providerid);

--
-- Name: Podcasts fk_podcasts_feed; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public."Podcasts"
    ADD CONSTRAINT fk_podcasts_feed FOREIGN KEY (feedid) REFERENCES public."Feeds"(feedid) ON DELETE SET NULL;
