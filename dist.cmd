@echo off

set FILES=SU2XPlane*.html SU2XPlane.rb

if exist SU2XPlane.zip del SU2XPlane.zip
zip -9 SU2XPlane.zip %FILES%
