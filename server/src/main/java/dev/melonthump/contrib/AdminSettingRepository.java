package dev.melonthump.contrib;

import jakarta.persistence.LockModeType;
import java.util.List;
import java.util.Optional;
import org.springframework.data.jpa.repository.Lock;
import org.springframework.data.jpa.repository.Query;
import org.springframework.data.repository.Repository;
import org.springframework.data.repository.query.Param;

/** Runtime setting overrides (V7). */
public interface AdminSettingRepository extends Repository<AdminSetting, String> {

    <S extends AdminSetting> S saveAndFlush(S setting);

    List<AdminSetting> findAll();

    @Lock(LockModeType.PESSIMISTIC_WRITE)
    @Query("select s from AdminSetting s where s.key = :key")
    Optional<AdminSetting> findForUpdate(@Param("key") String key);

    void delete(AdminSetting setting);

    void flush();
}
