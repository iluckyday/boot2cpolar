FROM archlinux as builder

COPY build.sh /tmp/
RUN chmod +x /tmp/build.sh
RUN /tmp/build.sh


FROM scratch

COPY --from=builder /tmp/boot2cpolar.iso /
