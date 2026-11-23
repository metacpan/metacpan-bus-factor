requires 'Cpanel::JSON::XS';
requires 'DateTime';
requires 'Exporter';
requires 'List::Util';
requires 'MetaCPAN::Client', '2.039000';
requires 'Module::CoreList';
requires 'Path::Tiny';
requires 'Ref::Util';

on test => sub {
    requires 'Test2::V0';
};
